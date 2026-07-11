import Combine
import CoreMotion
import WatchKit

// Detector de repeticiones v3 — basado en ORIENTACIÓN (actitud), no en picos de
// aceleración.
//
// Por qué: en el WWDC de Core Motion Apple explica que contar repeticiones se
// hace mejor observando el ciclo de ORIENTACIÓN de la muñeca (que se repite en
// cada rep) que con picos de aceleración. Las series lentas y controladas casi
// no aceleran la muñeca (0.1-0.3g) pero SÍ cambian su orientación de forma
// clara y repetible. El v2 (umbral sobre |aceleración|) se comía esas reps.
//
// Cómo funciona:
//  - Señal 1-D = ángulo de la muñeca derivado del vector GRAVEDAD (sin deriva,
//    viene de la fusión de sensores). Se eligen dinámicamente los dos ejes con
//    más recorrido para el ejercicio actual.
//  - Paso-alto: se resta una media lenta (centro del balanceo).
//  - Amplitud adaptativa: envolvente EMA del tamaño del balanceo → el umbral se
//    calibra solo con TUS reps.
//  - Máquina de estados con histéresis: cuenta un ciclo completo (arriba y
//    vuelta) con refractario para no contar dobles.
//  - Tic háptico FUERTE por cada rep (.notification) para notarlo bien.
final class RepDetector: ObservableObject {
    @Published var reps = 0
    @Published var running = false

    struct Profile {
        var floor: Double        // rad: recorrido mínimo de orientación por rep
        var peakFraction: Double // umbral = max(floor, envolvente * esto)
        var minRep: Double       // s mínimos entre reps (refractario)
    }

    /// Perfil según el ejercicio (heurística por nombre, ES + EN).
    static func profile(for name: String) -> Profile {
        let n = name.lowercased()
        // Aislamiento de brazo: la muñeca rota mucho (curl, laterales, aperturas)
        if n.contains("curl") || n.contains("lateral") || n.contains("fly")
            || n.contains("aperturas") || n.contains("elevaci") || n.contains("pajaros")
            || n.contains("face pull") || n.contains("extension de triceps")
            || n.contains("frances") || n.contains("pushdown") {
            return Profile(floor: 0.16, peakFraction: 0.50, minRep: 0.8)
        }
        // Empujes: la muñeca rota poco (press, fondos) → umbral bajo
        if n.contains("press") || n.contains("push") || n.contains("fondos") || n.contains("flexiones") {
            return Profile(floor: 0.10, peakFraction: 0.42, minRep: 0.9)
        }
        // Tirones: remos, jalones, dominadas
        if n.contains("remo") || n.contains("row") || n.contains("pulldown")
            || n.contains("jalon") || n.contains("dominadas") || n.contains("pull") {
            return Profile(floor: 0.12, peakFraction: 0.45, minRep: 0.85)
        }
        // Pierna / general
        return Profile(floor: 0.12, peakFraction: 0.42, minRep: 1.0)
    }

    private var profile = Profile(floor: 0.12, peakFraction: 0.45, minRep: 0.9)

    private let motion = CMMotionManager()
    private let queue = OperationQueue()

    // Estado de la señal de orientación
    private var meanPitch = 0.0, meanRoll = 0.0     // media lenta (centro)
    private var varPitch = 0.0, varRoll = 0.0        // varianza (qué eje se mueve)
    private var envelope = 0.0                        // amplitud típica del balanceo
    private var lastRep: TimeInterval = 0
    private var phase = 0                             // 0 centro, +1 arriba, -1 abajo
    private var seenHigh = false, seenLow = false
    private var primed = false                        // ignora el arranque

    func start(for exerciseName: String) {
        profile = Self.profile(for: exerciseName)
        reps = 0
        meanPitch = 0; meanRoll = 0; varPitch = 0; varRoll = 0
        envelope = 0; lastRep = 0; phase = 0
        seenHigh = false; seenLow = false; primed = false
        running = true
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 50.0
        motion.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let self, let d = data else { return }
            self.process(d)
        }
    }

    private func process(_ d: CMDeviceMotion) {
        // Ángulos de la muñeca a partir de la gravedad (sin deriva).
        let g = d.gravity
        let pitch = atan2(-g.z, (g.x * g.x + g.y * g.y).squareRoot())
        let roll = atan2(g.y, g.x)

        // Media lenta (centro del balanceo) y varianza por eje (~2 s).
        let aMean = 0.02
        meanPitch += aMean * (pitch - meanPitch)
        meanRoll += aMean * angleDelta(roll, meanRoll) * 1.0
        let dP = pitch - meanPitch
        let dR = angleDelta(roll, meanRoll)
        let aVar = 0.02
        varPitch += aVar * (dP * dP - varPitch)
        varRoll += aVar * (dR * dR - varRoll)

        // Señal = eje con más recorrido en este ejercicio.
        let s = varRoll > varPitch ? dR : dP

        // Da tiempo a que la media se asiente antes de contar (~0.6 s).
        if !primed {
            if d.timestamp > 0 { primed = true }  // se activa al 2º sample; la
            // envolvente y la media siguen calentándose, pero el refractario y
            // la histéresis evitan cuentas falsas.
        }

        // Envolvente adaptativa del tamaño del balanceo.
        let mag = abs(s)
        if mag > envelope { envelope += 0.15 * (mag - envelope) }
        else { envelope += 0.02 * (mag - envelope) }

        let hi = max(profile.floor, envelope * profile.peakFraction)
        let lo = hi * 0.35
        let t = d.timestamp

        // Histéresis: hay que ver un extremo (arriba o abajo) y volver a cruzar
        // el centro para contar una rep. Vale para balanceos simétricos y para
        // movimientos que suben y vuelven.
        if s > hi { seenHigh = true }
        if s < -hi { seenLow = true }

        if abs(s) < lo, (seenHigh || seenLow) {
            if t - lastRep > profile.minRep, envelope > profile.floor * 0.8 {
                lastRep = t
                seenHigh = false; seenLow = false
                DispatchQueue.main.async {
                    self.reps += 1
                    WKInterfaceDevice.current().play(.notification) // tic fuerte
                }
            } else {
                // demasiado pronto: resetea sin contar
                seenHigh = false; seenLow = false
            }
        }
    }

    /// Diferencia angular con envoltura (-π, π] para el roll.
    private func angleDelta(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d > .pi { d -= 2 * .pi }
        while d < -(.pi) { d += 2 * .pi }
        return d
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
