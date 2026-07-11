import Combine
import CoreMotion
import WatchKit

// Detector de repeticiones v8 — por TRASLACIÓN de la mano (sin deriva).
//
// En máquina la muñeca NO gira: solo se traslada por el espacio. Por eso no
// sirve ni la orientación (no cambia) ni integrar la velocidad (deriva).
//
// Lo que sí es fiable: la ACELERACIÓN del usuario a lo largo del eje del
// movimiento. En cada cambio de sentido (los extremos del recorrido: cerca/
// lejos, arriba/abajo) la mano frena y acelera al revés → hay un PICO de
// aceleración. Contamos esos picos: uno por repetición. No se integra nada, así
// que no hay deriva ni con repes lentas.
//
//  - Eje del movimiento = eje de mayor varianza de la aceleración (estable en
//    máquina porque la orientación del reloj es fija).
//  - Prominencia adaptativa + amplitud parecida a tus repes + refractario →
//    ignora ruido, micro-movimientos y el gesto de girar para terminar.
//  - .manual: máquinas de pierna (la mano no se mueve) → se cuenta con +/−.
final class RepDetector: ObservableObject {
    @Published var reps = 0
    @Published var running = false
    @Published var manual = false

    enum Mode { case auto, manual }

    struct Profile {
        var mode: Mode
        var minAmp: Double   // g: amplitud mínima del pico de aceleración por repe
        var minRep: Double   // s mínimos entre repes
    }

    static func profile(for name: String) -> Profile {
        let n = name.lowercased()
        if n.contains("leg extension") || n.contains("leg curl") || n.contains("leg press")
            || n.contains("extension de cuadriceps") || n.contains("extensión de cuádriceps")
            || n.contains("curl femoral") || n.contains("femoral")
            || n.contains("prensa") || n.contains("quad") {
            return Profile(mode: .manual, minAmp: 0, minRep: 0)
        }
        return Profile(mode: .auto, minAmp: 0.10, minRep: 0.7)
    }

    private var profile = Profile(mode: .auto, minAmp: 0.10, minRep: 0.7)

    private let motion = CMMotionManager()
    private let queue = OperationQueue()

    // Media y varianza por eje de la aceleración (para elegir el eje del movimiento).
    private var mean = [0.0, 0.0, 0.0]
    private var vari = [0.0, 0.0, 0.0]
    private var smooth = 0.0          // señal suavizada del eje elegido
    private var primed = false

    // Detección de picos/valles.
    private var searchingPeak = true
    private var ext = 0.0
    private var extT: TimeInterval = 0
    private var haveValley = false
    private var amp = 0.3
    private var lastRep: TimeInterval = 0
    private var lastValleyVal = 0.0

    func start(for exerciseName: String) {
        profile = Self.profile(for: exerciseName)
        reps = 0
        mean = [0, 0, 0]; vari = [0, 0, 0]; smooth = 0; primed = false
        searchingPeak = true; ext = 0; extT = 0; haveValley = false
        amp = 0.3; lastRep = 0; lastValleyVal = 0
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
        let a = [d.userAcceleration.x, d.userAcceleration.y, d.userAcceleration.z]

        // Media (sesgo) y varianza por eje.
        for i in 0..<3 {
            mean[i] += 0.02 * (a[i] - mean[i])
            let dev = a[i] - mean[i]
            vari[i] += 0.02 * (dev * dev - vari[i])
        }
        // Eje del movimiento = el de mayor varianza.
        var axis = 0
        if vari[1] > vari[axis] { axis = 1 }
        if vari[2] > vari[axis] { axis = 2 }

        // Señal centrada y suavizada (~4 muestras) para quitar temblor.
        let raw = a[axis] - mean[axis]
        smooth = 0.3 * raw + 0.7 * smooth

        if !primed { ext = smooth; primed = true }

        let prom = max(0.04, 0.30 * amp)

        if searchingPeak {
            if smooth > ext { ext = smooth; extT = t }
            if smooth < ext - prom {                  // confirma PICO
                onPeak(value: ext, t: extT)
                searchingPeak = false
                ext = smooth
            }
        } else {
            if smooth < ext { ext = smooth; extT = t }
            if smooth > ext + prom {                   // confirma VALLE
                lastValleyVal = ext
                haveValley = true
                searchingPeak = true
                ext = smooth
            }
        }
    }

    private func onPeak(value: Double, t: TimeInterval) {
        let ptp = value - lastValleyVal
        if ptp > profile.minAmp { amp += 0.25 * (ptp - amp) }

        let amplitudeOK = ptp > profile.minAmp && ptp > 0.5 * amp
        if haveValley, amplitudeOK, t - lastRep > profile.minRep {
            lastRep = t
            haveValley = false
            DispatchQueue.main.async {
                self.reps += 1
                WKInterfaceDevice.current().play(.notification)
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
