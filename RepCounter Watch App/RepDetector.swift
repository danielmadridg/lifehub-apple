import Combine
import CoreMotion
import WatchKit

// Detector de repeticiones v9 — pipeline tipo RecoFit / uLift.
//
// Basado en la literatura de conteo de repes con IMU de muñeca (RecoFit, uLift
// y patentes de Apple/otros). Pasos:
//  1. Aceleración del usuario (sin gravedad) a 50 Hz.
//  2. Paso-alto → quita sesgo/deriva lenta.
//  3. Integra a velocidad + paso-alto de nuevo → señal de velocidad de banda de
//     repe SIN deriva (esto evita las ráfagas de conteo).
//  4. PCA en tiempo real (iteración de potencia): proyecta los 3 ejes al EJE
//     PRINCIPAL del movimiento → 1 señal. Capta bien el arco del pec fly y la
//     línea del chest press sin depender de un eje fijo.
//  5. Detección de ciclo con histéresis: la velocidad cruza cero en cada extremo
//     del recorrido → cuenta una repe por ciclo completo, con refractario.
//
//  .manual: máquinas de pierna (la muñeca no se mueve) → se cuenta con +/−.
final class RepDetector: ObservableObject {
    @Published var reps = 0
    @Published var running = false
    @Published var manual = false

    enum Mode { case auto, manual }
    struct Profile { var mode: Mode; var floor: Double; var frac: Double; var minRep: Double }

    static func profile(for name: String) -> Profile {
        let n = name.lowercased()
        if n.contains("leg extension") || n.contains("leg curl") || n.contains("leg press")
            || n.contains("extension de cuadriceps") || n.contains("extensión de cuádriceps")
            || n.contains("curl femoral") || n.contains("femoral")
            || n.contains("prensa") || n.contains("quad") {
            return Profile(mode: .manual, floor: 0, frac: 0, minRep: 0)
        }
        return Profile(mode: .auto, floor: 0.045, frac: 0.40, minRep: 0.7)
    }

    private var profile = Profile(mode: .auto, floor: 0.045, frac: 0.40, minRep: 0.7)

    private let motion = CMMotionManager()
    private let queue = OperationQueue()

    // Filtros (por eje)
    private var aPrev = [0.0, 0.0, 0.0]
    private var aHP = [0.0, 0.0, 0.0]
    private var vel = [0.0, 0.0, 0.0]
    private var velPrev = [0.0, 0.0, 0.0]
    private var velHP = [0.0, 0.0, 0.0]
    // Covarianza (simétrica 3x3) y eje principal (PCA por iteración de potencia)
    private var c00 = 0.0, c01 = 0.0, c02 = 0.0, c11 = 0.0, c12 = 0.0, c22 = 0.0
    private var pc = [1.0, 0.0, 0.0]
    // Detección de ciclo
    private var sm = 0.0
    private var envelope = 0.0
    private var seenPos = false, seenNeg = false
    private var lastRep: TimeInterval = 0
    private var lastT: TimeInterval = 0

    func start(for exerciseName: String) {
        profile = Self.profile(for: exerciseName)
        reps = 0
        aPrev = [0,0,0]; aHP = [0,0,0]; vel = [0,0,0]; velPrev = [0,0,0]; velHP = [0,0,0]
        c00 = 0; c01 = 0; c02 = 0; c11 = 0; c12 = 0; c22 = 0; pc = [1,0,0]
        sm = 0; envelope = 0; seenPos = false; seenNeg = false; lastRep = 0; lastT = 0
        running = true
        manual = profile.mode == .manual

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

        let a = [d.userAcceleration.x, d.userAcceleration.y, d.userAcceleration.z]

        // Paso-alto de la aceleración (RC ~1s) → quita sesgo.
        let hpA = 1.0 / (1.0 + dt)              // ≈0.98
        for i in 0..<3 {
            aHP[i] = hpA * (aHP[i] + a[i] - aPrev[i])
            aPrev[i] = a[i]
            // Integra a velocidad y paso-alto (RC ~1.5s) → sin deriva.
            vel[i] += aHP[i] * 9.81 * dt
            let hpV = 1.5 / (1.5 + dt)           // ≈0.987
            velHP[i] = hpV * (velHP[i] + vel[i] - velPrev[i])
            velPrev[i] = vel[i]
        }

        // Covarianza incremental de la velocidad (ventana ~1s).
        let x = velHP, aCov = 0.02
        c00 += aCov * (x[0]*x[0] - c00); c01 += aCov * (x[0]*x[1] - c01); c02 += aCov * (x[0]*x[2] - c02)
        c11 += aCov * (x[1]*x[1] - c11); c12 += aCov * (x[1]*x[2] - c12); c22 += aCov * (x[2]*x[2] - c22)
        // Iteración de potencia: pc ← normalize(C·pc). Converge al eje principal.
        let m0 = c00*pc[0] + c01*pc[1] + c02*pc[2]
        let m1 = c01*pc[0] + c11*pc[1] + c12*pc[2]
        let m2 = c02*pc[0] + c12*pc[1] + c22*pc[2]
        let mn = (m0*m0 + m1*m1 + m2*m2).squareRoot()
        if mn > 1e-9 {
            var nv = [m0/mn, m1/mn, m2/mn]
            // Continuidad de signo (el autovector puede invertirse).
            if nv[0]*pc[0] + nv[1]*pc[1] + nv[2]*pc[2] < 0 { nv = [-nv[0], -nv[1], -nv[2]] }
            pc = nv
        }

        // Proyección a 1D + suavizado ligero.
        let s = velHP[0]*pc[0] + velHP[1]*pc[1] + velHP[2]*pc[2]
        sm = 0.4 * s + 0.6 * sm

        // Envolvente adaptativa.
        let mag = abs(sm)
        if mag > envelope { envelope += 0.15 * (mag - envelope) }
        else { envelope += 0.02 * (mag - envelope) }

        let hi = max(profile.floor, envelope * profile.frac)
        let lo = hi * 0.30

        // La velocidad cruza cero en cada EXTREMO del recorrido; una repe = un
        // ciclo completo (subió/avanzó y volvió).
        if sm > hi { seenPos = true }
        if sm < -hi { seenNeg = true }
        if abs(sm) < lo, seenPos, seenNeg {
            if t - lastRep > profile.minRep, envelope > profile.floor {
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

    func adjust(_ delta: Int) {
        reps = max(0, reps + delta)
        if delta > 0 { WKInterfaceDevice.current().play(.click) }
    }
}
