import Combine
import CoreMotion
import WatchKit

// Detector de repeticiones v10 — pipeline tipo RecoFit/uLift + gestos.
//
// Conteo (RepDetector): aceleración → paso-alto → integra a velocidad →
// paso-alto (sin deriva) → PCA en tiempo real (eje principal del movimiento) →
// conteo de ciclos por histéresis. Capta el arco del pec fly y la línea del
// chest press sin fijar un eje.
//
// Novedades:
//  - Monitoriza el sensor SIEMPRE que la vista está abierta (aunque no cuentes),
//    para detectar una SACUDIDA de muñeca → empezar/terminar serie sin tocar la
//    pantalla.
//  - 1 s de gracia al empezar la serie: ignora el movimiento mientras recolocas
//    las manos (y deja calentar los filtros y el PCA → cuenta desde la 1ª repe).
//
//  .manual: máquinas de pierna → se cuenta con +/− (pero la sacudida vale igual).
final class RepDetector: ObservableObject {
    @Published var reps = 0
    @Published var running = false      // ¿contando una serie?
    @Published var manual = false
    @Published var shakeCount = 0       // sube al detectar una sacudida de muñeca

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
    private let graceStart = 1.0        // s de gracia tras empezar la serie

    private let motion = CMMotionManager()
    private let queue = OperationQueue()

    // Estado de conteo
    private var counting = false
    private var setStartT: TimeInterval = -1

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
    // Detección de sacudida
    private var spikeTimes: [TimeInterval] = []
    private var lastShake: TimeInterval = 0

    // ── Ciclo de vida ────────────────────────────────────────────────────────

    /// Empieza a leer el sensor (para detectar sacudidas), sin contar todavía.
    func startMonitoring() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 50.0
        motion.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let self, let d = data else { return }
            self.process(d)
        }
    }

    func stopMonitoring() {
        counting = false
        running = false
        motion.stopDeviceMotionUpdates()
    }

    /// Empieza a contar una serie del ejercicio dado.
    func beginSet(for exerciseName: String) {
        profile = Self.profile(for: exerciseName)
        reps = 0
        aPrev = [0,0,0]; aHP = [0,0,0]; vel = [0,0,0]; velPrev = [0,0,0]; velHP = [0,0,0]
        c00 = 0; c01 = 0; c02 = 0; c11 = 0; c12 = 0; c22 = 0; pc = [1,0,0]
        sm = 0; envelope = 0; seenPos = false; seenNeg = false; lastRep = 0
        setStartT = -1
        counting = true
        running = true
        manual = profile.mode == .manual
        startMonitoring()   // por si no estaba activo
    }

    /// Termina de contar (sigue monitorizando para la siguiente sacudida).
    func endSet() {
        counting = false
        running = false
    }

    // ── Proceso por muestra ──────────────────────────────────────────────────

    private func process(_ d: CMDeviceMotion) {
        let t = d.timestamp
        let dt = lastT > 0 ? min(0.1, t - lastT) : 1.0 / 50.0
        lastT = t

        detectShake(d, t: t)

        guard counting, !manual else { return }

        // Gracia inicial: deja calentar filtros/PCA sin contar (recolocas manos).
        if setStartT < 0 { setStartT = t }
        let warming = (t - setStartT) < graceStart

        let a = [d.userAcceleration.x, d.userAcceleration.y, d.userAcceleration.z]

        let hpA = 1.0 / (1.0 + dt)
        let hpV = 1.5 / (1.5 + dt)
        for i in 0..<3 {
            aHP[i] = hpA * (aHP[i] + a[i] - aPrev[i])
            aPrev[i] = a[i]
            vel[i] += aHP[i] * 9.81 * dt
            velHP[i] = hpV * (velHP[i] + vel[i] - velPrev[i])
            velPrev[i] = vel[i]
        }

        // Covarianza (convergencia rápida) + iteración de potencia (x2).
        let x = velHP, aCov = 0.04
        c00 += aCov*(x[0]*x[0]-c00); c01 += aCov*(x[0]*x[1]-c01); c02 += aCov*(x[0]*x[2]-c02)
        c11 += aCov*(x[1]*x[1]-c11); c12 += aCov*(x[1]*x[2]-c12); c22 += aCov*(x[2]*x[2]-c22)
        for _ in 0..<2 {
            let m0 = c00*pc[0]+c01*pc[1]+c02*pc[2]
            let m1 = c01*pc[0]+c11*pc[1]+c12*pc[2]
            let m2 = c02*pc[0]+c12*pc[1]+c22*pc[2]
            let mn = (m0*m0+m1*m1+m2*m2).squareRoot()
            if mn > 1e-9 {
                var nv = [m0/mn, m1/mn, m2/mn]
                if nv[0]*pc[0]+nv[1]*pc[1]+nv[2]*pc[2] < 0 { nv = [-nv[0], -nv[1], -nv[2]] }
                pc = nv
            }
        }

        let s = velHP[0]*pc[0] + velHP[1]*pc[1] + velHP[2]*pc[2]
        sm = 0.4 * s + 0.6 * sm

        let mag = abs(sm)
        if mag > envelope { envelope += 0.15*(mag-envelope) } else { envelope += 0.02*(mag-envelope) }

        if warming { return }   // filtros calientes, pero aún no contamos

        let hi = max(profile.floor, envelope * profile.frac)
        let lo = hi * 0.30
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

    /// Sacudida = varios picos fuertes y rápidos (mucho más violentos que una
    /// repe, que es lenta y suave), en < ~0.9 s.
    private func detectShake(_ d: CMDeviceMotion, t: TimeInterval) {
        let a = d.userAcceleration, r = d.rotationRate
        let acc = (a.x*a.x + a.y*a.y + a.z*a.z).squareRoot()
        let rot = (r.x*r.x + r.y*r.y + r.z*r.z).squareRoot()
        if acc > 1.6 || rot > 9.0 {
            if spikeTimes.last.map({ t - $0 > 0.08 }) ?? true {  // separa picos
                spikeTimes.append(t)
            }
        }
        spikeTimes.removeAll { t - $0 > 0.9 }
        if spikeTimes.count >= 4, t - lastShake > 1.5 {
            lastShake = t
            spikeTimes.removeAll()
            DispatchQueue.main.async {
                WKInterfaceDevice.current().play(.success)
                self.shakeCount += 1
            }
        }
    }

    func adjust(_ delta: Int) {
        reps = max(0, reps + delta)
        if delta > 0 { WKInterfaceDevice.current().play(.click) }
    }
}
