import Combine
import CoreMotion
import WatchKit

// Detector de repeticiones v5 — por TIPO de movimiento del ejercicio.
//
// Cada ejercicio se cuenta según cómo se mueve la mano:
//  - .vertical   : la mano sube y baja (press, curl, jalón, elevaciones…). Se
//                  mide la velocidad VERTICAL (aceleración proyectada sobre la
//                  gravedad).
//  - .horizontal : la mano se acerca/aleja del cuerpo (chest press, pec fly,
//                  seated row, cruces). Se mide la velocidad en el PLANO
//                  horizontal, sobre su eje principal.
//  - .manual     : máquinas de pierna donde la muñeca no se mueve. No hay
//                  auto-conteo: se cuenta con los botones +/−.
//
// En vertical y horizontal se cuenta una repe por ciclo completo (ida y vuelta)
// con envolvente adaptativa, histéresis y refractario. Tic háptico fuerte por repe.
final class RepDetector: ObservableObject {
    @Published var reps = 0
    @Published var running = false
    @Published var manual = false

    enum Mode { case vertical, horizontal, manual }

    struct Profile {
        var mode: Mode
        var floor: Double        // m/s: amplitud mínima de velocidad
        var peakFraction: Double
        var minRep: Double       // s entre repes
    }

    /// Modo + parámetros según el ejercicio (nombre, ES + EN).
    static func profile(for name: String) -> Profile {
        let n = name.lowercased()

        // Máquinas de pierna: la muñeca no se mueve → manual.
        if n.contains("leg extension") || n.contains("leg curl") || n.contains("leg press")
            || n.contains("extension de cuadriceps") || n.contains("extensión de cuádriceps")
            || n.contains("curl femoral") || n.contains("femoral")
            || n.contains("prensa") || n.contains("quad") {
            return Profile(mode: .manual, floor: 0, peakFraction: 0, minRep: 0)
        }

        // Movimientos horizontales (acercar/alejar del cuerpo).
        if n.contains("chest press") || n.contains("pec fly") || n.contains("pec deck")
            || n.contains("cable row") || n.contains("seated row") || n.contains("crossover")
            || n.contains("cruces") || n.contains("aperturas en polea") {
            return Profile(mode: .horizontal, floor: 0.08, peakFraction: 0.42, minRep: 0.8)
        }

        // Resto: vertical (sube/baja).
        return Profile(mode: .vertical, floor: 0.08, peakFraction: 0.42, minRep: 0.85)
    }

    private var profile = Profile(mode: .vertical, floor: 0.08, peakFraction: 0.42, minRep: 0.85)

    private let motion = CMMotionManager()
    private let queue = OperationQueue()

    // Integración / detección
    private var meanAcc = 0.0
    private var vel = 0.0                       // velocidad a lo largo del eje activo
    private var velH = SIMD3<Double>(0, 0, 0)   // velocidad horizontal (3D en plano ⊥ g)
    private var pDir = SIMD3<Double>(0, 0, 0)   // eje horizontal principal
    private var envelope = 0.0
    private var lastT: TimeInterval = 0
    private var lastRep: TimeInterval = 0
    private var seenPos = false, seenNeg = false

    func start(for exerciseName: String) {
        profile = Self.profile(for: exerciseName)
        reps = 0
        meanAcc = 0; vel = 0; velH = .zero; pDir = .zero
        envelope = 0; lastT = 0; lastRep = 0
        seenPos = false; seenNeg = false
        running = true
        manual = profile.mode == .manual

        // En manual no se arranca el sensor: se cuenta con los botones.
        guard profile.mode != .manual, motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 50.0
        motion.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let self, let d = data else { return }
            self.process(d)
        }
    }

    private func process(_ d: CMDeviceMotion) {
        let t = d.timestamp
        let dt = lastT > 0 ? min(0.1, t - lastT) : 1.0 / 50.0
        lastT = t

        let a = SIMD3(d.userAcceleration.x, d.userAcceleration.y, d.userAcceleration.z)
        let g = SIMD3(d.gravity.x, d.gravity.y, d.gravity.z)  // |g| ~ 1

        let s: Double
        if profile.mode == .horizontal {
            // Aceleración en el plano horizontal (quita la componente vertical).
            let vertComp = dot(a, g)
            let aH = (a - g * vertComp) * 9.81
            velH = velH * 0.95 + aH * dt
            // Eje principal = EMA de la dirección de la velocidad horizontal.
            let speed = length(velH)
            if speed > 1e-4 {
                let dir = velH / speed
                pDir = pDir + 0.05 * (dir - pDir)
                if length(pDir) > 1e-4 { pDir = normalize(pDir) }
            }
            s = dot(velH, pDir)   // velocidad con signo a lo largo del eje del ejercicio
        } else {
            // Vertical: aceleración proyectada sobre la gravedad.
            let vertAcc = dot(a, g)
            meanAcc += 0.02 * (vertAcc - meanAcc)
            let aHP = (vertAcc - meanAcc) * 9.81
            vel = vel * 0.95 + aHP * dt
            s = vel
        }

        // Envolvente adaptativa.
        let mag = abs(s)
        if mag > envelope { envelope += 0.15 * (mag - envelope) }
        else { envelope += 0.02 * (mag - envelope) }

        let hi = max(profile.floor, envelope * profile.peakFraction)
        let lo = hi * 0.30

        if s > hi { seenPos = true }
        if s < -hi { seenNeg = true }

        if abs(s) < lo, seenPos, seenNeg {
            if t - lastRep > profile.minRep, envelope > profile.floor * 0.8 {
                lastRep = t
                seenPos = false; seenNeg = false
                DispatchQueue.main.async {
                    self.reps += 1
                    WKInterfaceDevice.current().play(.notification)
                }
            } else {
                seenPos = false; seenNeg = false
            }
        }
    }

    func stop() {
        running = false
        motion.stopDeviceMotionUpdates()
    }

    /// Corrección manual (+/-). En ejercicios .manual es la única forma de contar.
    func adjust(_ delta: Int) {
        reps = max(0, reps + delta)
        if delta > 0 { WKInterfaceDevice.current().play(.click) }
    }
}
