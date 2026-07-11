import Combine
import CoreMotion
import WatchKit

// Detector de repeticiones v6 — cuenta en el EXTREMO del movimiento.
//
// Idea física: en un movimiento suave la velocidad es MÁXIMA a mitad de recorrido
// y CERO en los extremos (arriba/abajo, cerca/lejos). Por eso contamos en el
// cruce por cero de la velocidad (= punto de giro = extremo), no a mitad.
//
// Por tipo:
//  - .vertical  : velocidad vertical (aceleración proyectada sobre la gravedad,
//                 con signo: + = hacia arriba). Cuenta arriba (countHigh) o abajo.
//  - .horizontal: velocidad en el plano horizontal sobre su eje principal. El
//                 extremo que cuenta es el que cierra la fase MÁS FUERTE (la
//                 concéntrica: empujar en press, cerrar en pec fly, tirar en row).
//  - .manual    : no auto-cuenta (máquinas de pierna); se usa +/−.
//
// Para NO contar de más: exige un CICLO COMPLETO (fase opuesta previa) antes de
// cada conteo. Así, girar la muñeca para pulsar "Terminar" no suma otra repe,
// porque no viene precedido de la fase opuesta.
final class RepDetector: ObservableObject {
    @Published var reps = 0
    @Published var running = false
    @Published var manual = false

    enum Mode { case vertical, horizontal, manual }

    struct Profile {
        var mode: Mode
        var countHigh: Bool      // (vertical) contar arriba (true) o abajo (false)
        var floor: Double        // m/s: amplitud mínima de velocidad
        var peakFraction: Double
        var minRep: Double
    }

    static func profile(for name: String) -> Profile {
        let n = name.lowercased()

        // Máquinas de pierna → manual.
        if n.contains("leg extension") || n.contains("leg curl") || n.contains("leg press")
            || n.contains("extension de cuadriceps") || n.contains("extensión de cuádriceps")
            || n.contains("curl femoral") || n.contains("femoral")
            || n.contains("prensa") || n.contains("quad") {
            return Profile(mode: .manual, countHigh: true, floor: 0, peakFraction: 0, minRep: 0)
        }

        // Horizontales (acercar/alejar del cuerpo).
        if n.contains("chest press") || n.contains("pec fly") || n.contains("pec deck")
            || n.contains("cable row") || n.contains("seated row") || n.contains("crossover")
            || n.contains("cruces") || n.contains("aperturas en polea") {
            return Profile(mode: .horizontal, countHigh: true, floor: 0.09, peakFraction: 0.45, minRep: 0.9)
        }

        // Verticales que cuentan ABAJO (contracción abajo): jalones, pushdown.
        let down = n.contains("pulldown") || n.contains("pull-down") || n.contains("pull down")
            || n.contains("jalon") || n.contains("jalón") || n.contains("pushdown")
            || n.contains("push-down") || n.contains("push down")

        return Profile(mode: .vertical, countHigh: !down, floor: 0.08, peakFraction: 0.45, minRep: 0.9)
    }

    private var profile = Profile(mode: .vertical, countHigh: true, floor: 0.08, peakFraction: 0.45, minRep: 0.9)

    private let motion = CMMotionManager()
    private let queue = OperationQueue()

    private var meanAcc = 0.0
    private var vel = 0.0
    private var velH = SIMD3<Double>(0, 0, 0)
    private var pDir = SIMD3<Double>(0, 0, 0)
    private var envelope = 0.0
    private var lastT: TimeInterval = 0
    private var lastRep: TimeInterval = 0

    // Fase actual del movimiento
    private var phaseSign = 0          // +1 subiendo/avanzando, -1 bajando/volviendo
    private var phasePeak = 0.0        // pico de |v| en la fase actual
    private var oppSeen = false        // ¿hubo fase opuesta fuerte desde el último conteo?
    // Aprendizaje del extremo que cuenta en horizontales
    private var hTargetSign = 0
    private var learnPos = 0.0, learnNeg = 0.0

    func start(for exerciseName: String) {
        profile = Self.profile(for: exerciseName)
        reps = 0
        meanAcc = 0; vel = 0; velH = .zero; pDir = .zero
        envelope = 0; lastT = 0; lastRep = 0
        phaseSign = 0; phasePeak = 0; oppSeen = false
        hTargetSign = 0; learnPos = 0; learnNeg = 0
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

        let a = SIMD3(d.userAcceleration.x, d.userAcceleration.y, d.userAcceleration.z)
        let g = SIMD3(d.gravity.x, d.gravity.y, d.gravity.z)

        // Señal de velocidad con signo a lo largo del eje activo. Fuga SUAVE
        // (0.995 ≈ 2 s) para no matar repes lentas.
        var v: Double
        if profile.mode == .horizontal {
            let vertComp = dot(a, g)
            let aH = (a - g * vertComp) * 9.81
            velH = velH * 0.995 + aH * dt
            let speed = length(velH)
            if speed > 1e-4 {
                let dir = velH / speed
                pDir = pDir + 0.05 * (dir - pDir)
                if length(pDir) > 1e-4 { pDir = normalize(pDir) }
            }
            v = dot(velH, pDir)
        } else {
            // + = hacia arriba (aceleración opuesta a la gravedad).
            let upAcc = -dot(a, g)
            meanAcc += 0.01 * (upAcc - meanAcc)
            vel = vel * 0.995 + (upAcc - meanAcc) * 9.81 * dt
            v = vel
        }

        // Envolvente adaptativa de la amplitud de velocidad.
        let mag = abs(v)
        if mag > envelope { envelope += 0.15 * (mag - envelope) }
        else { envelope += 0.02 * (mag - envelope) }

        let hi = max(profile.floor, envelope * profile.peakFraction)
        let lo = hi * 0.25

        // Seguimiento de fase: arranca/mantiene la fase cuando |v| supera hi.
        if v > hi {
            if phaseSign <= 0 { phaseSign = 1; phasePeak = 0 }
            phasePeak = max(phasePeak, v)
        } else if v < -hi {
            if phaseSign >= 0 { phaseSign = -1; phasePeak = 0 }
            phasePeak = max(phasePeak, -v)
        } else if abs(v) < lo, phaseSign != 0, phasePeak > hi {
            // Cruce por cero tras una fase fuerte = EXTREMO (punto de giro).
            turningPoint(endedSign: phaseSign, peak: phasePeak, t: t)
            phaseSign = 0; phasePeak = 0
        }
    }

    private func turningPoint(endedSign: Int, peak: Double, t: TimeInterval) {
        // Determina qué signo de fase "cuenta" (concéntrica).
        let target: Int
        if profile.mode == .horizontal {
            if hTargetSign == 0 {
                // Aprende con el primer ciclo: la fase de mayor pico es la concéntrica.
                if endedSign > 0 { learnPos = max(learnPos, peak) } else { learnNeg = max(learnNeg, peak) }
                if learnPos > profile.floor, learnNeg > profile.floor {
                    hTargetSign = learnPos >= learnNeg ? 1 : -1
                }
                oppSeen = true      // durante el aprendizaje no contamos aún
                return
            }
            target = hTargetSign
        } else {
            target = profile.countHigh ? 1 : -1
        }

        if endedSign == target {
            // Extremo que cuenta: exige ciclo completo previo y refractario.
            if oppSeen, t - lastRep > profile.minRep {
                lastRep = t
                oppSeen = false
                DispatchQueue.main.async {
                    self.reps += 1
                    WKInterfaceDevice.current().play(.notification)
                }
            }
        } else {
            // Extremo opuesto (fase excéntrica): habilita el siguiente conteo.
            oppSeen = true
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
