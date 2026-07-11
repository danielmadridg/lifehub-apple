import Combine
import CoreMotion
import WatchKit

// Detector de repeticiones v2.
//
// El v1 usaba un umbral FIJO de 1.15g: las series lentas y controladas al fallo
// generan 0.1-0.3g en la muñeca, por eso se comía reps. Este usa:
//  - señal combinada: aceleración del usuario + giro (el giro pilla los curls)
//  - suavizado EMA para quitar temblor
//  - UMBRAL ADAPTATIVO: se calibra solo con la amplitud de TUS primeras reps
//    (envolvente de pico con decaimiento), con un suelo mínimo por perfil
//  - histéresis + refractario para no contar dobles
//  - PERFIL POR EJERCICIO: parámetros según el tipo de movimiento (curl, press,
//    remo, pierna...), elegidos por el nombre del ejercicio
// Da un tic háptico en cada rep contada (así notas en la muñeca si va bien).
final class RepDetector: ObservableObject {
    @Published var reps = 0
    @Published var running = false

    struct Profile {
        var floor: Double        // g: suelo mínimo del umbral (movimiento pequeño)
        var peakFraction: Double // umbral = max(floor, envolvente * esto)
        var minRep: Double       // s mínimos entre reps (refractario)
        var rotWeight: Double    // cuánto pesa el giro en la señal (curls giran mucho)
    }

    /// Perfil según el ejercicio (heurística por nombre, ES + EN).
    static func profile(for name: String) -> Profile {
        let n = name.lowercased()
        // Aislamiento de brazo: mucha excursión y giro de muñeca
        if n.contains("curl") || n.contains("lateral") || n.contains("fly")
            || n.contains("aperturas") || n.contains("elevaci") || n.contains("pajaros")
            || n.contains("face pull") || n.contains("extension de triceps")
            || n.contains("frances") || n.contains("pushdown") {
            return Profile(floor: 0.055, peakFraction: 0.45, minRep: 1.0, rotWeight: 0.12)
        }
        // Empujes: recorrido lineal, la muñeca acelera menos
        if n.contains("press") || n.contains("push") || n.contains("fondos") || n.contains("flexiones") {
            return Profile(floor: 0.045, peakFraction: 0.40, minRep: 1.2, rotWeight: 0.08)
        }
        // Tirones: remos, jalones, dominadas
        if n.contains("remo") || n.contains("row") || n.contains("pulldown")
            || n.contains("jalon") || n.contains("dominadas") || n.contains("pull") {
            return Profile(floor: 0.045, peakFraction: 0.40, minRep: 1.1, rotWeight: 0.08)
        }
        // Pierna / general: la muñeca casi ni se mueve → umbral muy bajo
        return Profile(floor: 0.035, peakFraction: 0.35, minRep: 1.4, rotWeight: 0.10)
    }

    private var profile = Profile(floor: 0.05, peakFraction: 0.40, minRep: 1.1, rotWeight: 0.10)

    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    private var ema = 0.0
    private var envelope = 0.0
    private var lastRep: TimeInterval = 0
    private var armed = true

    func start(for exerciseName: String) {
        profile = Self.profile(for: exerciseName)
        reps = 0
        ema = 0
        envelope = 0
        lastRep = 0
        armed = true
        running = true
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 50.0
        motion.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let self, let d = data else { return }
            let a = d.userAcceleration
            let r = d.rotationRate
            let acc = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            let rot = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
            let raw = acc + self.profile.rotWeight * rot

            // suavizado (~4 muestras) y envolvente de pico con decaimiento suave
            self.ema = 0.25 * raw + 0.75 * self.ema
            if self.ema > self.envelope {
                self.envelope = self.ema
            } else {
                self.envelope *= 0.998 // ~-10%/s: se adapta si bajas el ritmo
            }

            let hi = max(self.profile.floor, self.envelope * self.profile.peakFraction)
            let lo = hi * 0.5
            let t = d.timestamp

            if self.armed, self.ema > hi, t - self.lastRep > self.profile.minRep {
                self.lastRep = t
                self.armed = false
                DispatchQueue.main.async {
                    self.reps += 1
                    WKInterfaceDevice.current().play(.click) // tic por rep
                }
            } else if !self.armed, self.ema < lo {
                self.armed = true
            }
        }
    }

    func stop() {
        running = false
        motion.stopDeviceMotionUpdates()
    }

    /// Corrección manual (+/-) si contó de más o de menos.
    func adjust(_ delta: Int) {
        reps = max(0, reps + delta)
    }
}
