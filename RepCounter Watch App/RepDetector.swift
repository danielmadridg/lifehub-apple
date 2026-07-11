import Combine
import CoreMotion
import WatchKit

// Detector de repeticiones v7 — por ORIENTACIÓN de la muñeca (sin deriva).
//
// Por qué no velocidad: integrar la aceleración deriva y produce ráfagas de
// conteo (el curl "empezaba bien y luego contaba mucho de golpe") y en
// horizontal el eje se estimaba mal (chest press / pec fly no contaban nada).
//
// Este mide la DIRECCIÓN DE LA GRAVEDAD en el marco del reloj (viene de la
// fusión de sensores, no deriva). En casi todos los ejercicios la muñeca gira
// de forma repetible en cada repe: curl, press, elevaciones, chest press, pec
// fly, row, jalón… Se elige solo el eje que más varía, se detectan sus picos
// (extremos del recorrido) y se cuenta uno por repe.
//
//  - Filtro de amplitud: ignora micro-giros (y el gesto de girar para terminar).
//  - Prominencia adaptativa + refractario: no cuenta dobles ni ruido.
//  - .manual: máquinas de pierna (la muñeca no se mueve) → se cuenta con +/−.
final class RepDetector: ObservableObject {
    @Published var reps = 0
    @Published var running = false
    @Published var manual = false

    enum Mode { case auto, manual }

    struct Profile {
        var mode: Mode
        var minAmp: Double   // amplitud mínima del giro (pico-valle) por repe
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
        return Profile(mode: .auto, minAmp: 0.12, minRep: 0.7)
    }

    private var profile = Profile(mode: .auto, minAmp: 0.12, minRep: 0.7)

    private let motion = CMMotionManager()
    private let queue = OperationQueue()

    // Media y varianza por eje de la gravedad (para elegir el eje que más gira).
    private var mean = [0.0, 0.0, 0.0]
    private var vari = [0.0, 0.0, 0.0]
    private var primed = false

    // Detección de picos/valles sobre el eje elegido.
    private var searchingPeak = true
    private var ext = 0.0             // extremo en curso (máx si busca pico, mín si valle)
    private var extT: TimeInterval = 0
    private var haveValley = false    // ¿hubo un valle desde el último pico contado?
    private var amp = 0.2             // amplitud típica pico-valle (EMA)
    private var lastRep: TimeInterval = 0
    private var lastValleyVal = 0.0

    func start(for exerciseName: String) {
        profile = Self.profile(for: exerciseName)
        reps = 0
        mean = [0, 0, 0]; vari = [0, 0, 0]; primed = false
        searchingPeak = true; ext = 0; extT = 0; haveValley = false
        amp = 0.2; lastRep = 0; lastValleyVal = 0
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
        let g = [d.gravity.x, d.gravity.y, d.gravity.z]

        if !primed { mean = g; primed = true }

        // Media lenta y varianza por eje.
        for i in 0..<3 {
            mean[i] += 0.01 * (g[i] - mean[i])
            let dev = g[i] - mean[i]
            vari[i] += 0.01 * (dev * dev - vari[i])
        }
        // Eje que más gira en este ejercicio.
        var axis = 0
        if vari[1] > vari[axis] { axis = 1 }
        if vari[2] > vari[axis] { axis = 2 }

        let s = g[axis] - mean[axis]                 // señal centrada en 0
        let prom = max(0.05, 0.30 * amp)             // prominencia mínima del pico

        if searchingPeak {
            if s > ext { ext = s; extT = t }
            if s < ext - prom {                       // confirma un PICO en `ext`
                onPeak(value: ext, t: extT)
                searchingPeak = false
                ext = s                               // empieza a buscar el valle
            }
        } else {
            if s < ext { ext = s; extT = t }
            if s > ext + prom {                       // confirma un VALLE
                lastValleyVal = ext
                haveValley = true
                searchingPeak = true
                ext = s
            }
        }
    }

    private func onPeak(value: Double, t: TimeInterval) {
        let ptp = value - lastValleyVal               // amplitud pico-valle
        // Actualiza la amplitud típica solo con giros claros.
        if ptp > profile.minAmp { amp += 0.25 * (ptp - amp) }

        // Cuenta si: hubo un valle antes (ciclo completo), amplitud suficiente y
        // parecida a la de tus repes (descarta el gesto de terminar), y refractario.
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
