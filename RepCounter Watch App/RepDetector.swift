import Combine
import CoreMotion
import WatchKit

// Detector de repeticiones v4 — basado en el MOVIMIENTO VERTICAL de la mano
// (altura), no en la rotación de la muñeca.
//
// Por qué: contar por rotación de muñeca falla en muchos ejercicios (press,
// sentadilla, remo…) donde la muñeca casi no gira. Lo que SÍ es común a casi
// todo levantamiento es que la mano SUBE y BAJA una vez por repetición. Es lo
// que hacen las apps tipo "Train": miran el eje vertical del movimiento.
//
// Cómo:
//  - Se aísla la aceleración VERTICAL proyectando la aceleración del usuario
//    sobre el vector gravedad (eje "arriba" del mundo, sin importar cómo tengas
//    la muñeca).
//  - Se integra a VELOCIDAD vertical con fuga (paso-alto) para quitar la deriva:
//    la velocidad oscila +/- una vez por repe (subes y bajas).
//  - Amplitud adaptativa (envolvente) → el umbral se calibra con TUS repes.
//  - Máquina de estados con histéresis: cuenta un ciclo completo (sube y baja)
//    con refractario para no doblar.
//  - Tic háptico fuerte (.notification) por cada repe.
final class RepDetector: ObservableObject {
    @Published var reps = 0
    @Published var running = false

    struct Profile {
        var floor: Double        // m/s: amplitud mínima de velocidad vertical
        var peakFraction: Double // umbral = max(floor, envolvente * esto)
        var minRep: Double       // s mínimos entre repes (refractario)
    }

    /// Perfil según el ejercicio (heurística por nombre, ES + EN).
    static func profile(for name: String) -> Profile {
        let n = name.lowercased()
        // Recorrido grande y rápido (press, sentadilla, peso muerto, dominadas)
        if n.contains("press") || n.contains("sentadilla") || n.contains("squat")
            || n.contains("peso muerto") || n.contains("deadlift") || n.contains("hip thrust")
            || n.contains("dominadas") || n.contains("pull up") || n.contains("jalon")
            || n.contains("remo") || n.contains("row") {
            return Profile(floor: 0.10, peakFraction: 0.45, minRep: 0.8)
        }
        // Aislamiento de brazo/hombro: recorrido más corto (curl, laterales)
        if n.contains("curl") || n.contains("lateral") || n.contains("fly")
            || n.contains("aperturas") || n.contains("elevaci") || n.contains("pajaros")
            || n.contains("face pull") || n.contains("extension") || n.contains("frances")
            || n.contains("pushdown") || n.contains("patada") {
            return Profile(floor: 0.07, peakFraction: 0.42, minRep: 0.8)
        }
        // General
        return Profile(floor: 0.08, peakFraction: 0.42, minRep: 0.9)
    }

    private var profile = Profile(floor: 0.08, peakFraction: 0.42, minRep: 0.85)

    private let motion = CMMotionManager()
    private let queue = OperationQueue()

    private var meanAcc = 0.0      // media lenta de la aceleración vertical (sesgo)
    private var vel = 0.0          // velocidad vertical integrada (con fuga)
    private var envelope = 0.0     // amplitud típica de la velocidad
    private var lastT: TimeInterval = 0
    private var lastRep: TimeInterval = 0
    private var seenUp = false, seenDown = false

    func start(for exerciseName: String) {
        profile = Self.profile(for: exerciseName)
        reps = 0
        meanAcc = 0; vel = 0; envelope = 0; lastT = 0; lastRep = 0
        seenUp = false; seenDown = false
        running = true
        guard motion.isDeviceMotionAvailable else { return }
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

        // Aceleración vertical del usuario = proyección sobre la gravedad.
        // (gravedad tiene módulo ~1; el signo no importa para el ciclo.)
        let a = d.userAcceleration
        let g = d.gravity
        let vertAcc = a.x * g.x + a.y * g.y + a.z * g.z   // en g

        // Paso-alto: quita el sesgo lento.
        meanAcc += 0.02 * (vertAcc - meanAcc)
        let aHP = (vertAcc - meanAcc) * 9.81               // a m/s²

        // Integra a velocidad con fuga (evita que la deriva la dispare).
        vel = vel * 0.95 + aHP * dt

        // Envolvente adaptativa del tamaño de la oscilación de velocidad.
        let mag = abs(vel)
        if mag > envelope { envelope += 0.15 * (mag - envelope) }
        else { envelope += 0.02 * (mag - envelope) }

        let hi = max(profile.floor, envelope * profile.peakFraction)
        let lo = hi * 0.30

        // Histéresis: ver una fase de subida y otra de bajada (o al revés) y
        // volver a cruzar el centro = una repetición.
        if vel > hi { seenUp = true }
        if vel < -hi { seenDown = true }

        if abs(vel) < lo, seenUp, seenDown {
            if t - lastRep > profile.minRep, envelope > profile.floor * 0.8 {
                lastRep = t
                seenUp = false; seenDown = false
                DispatchQueue.main.async {
                    self.reps += 1
                    WKInterfaceDevice.current().play(.notification)
                }
            } else {
                seenUp = false; seenDown = false
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
