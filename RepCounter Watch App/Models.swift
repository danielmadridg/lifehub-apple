import Foundation

// Un ejercicio de la rutina de hoy (viene de GET /api/gym/device/today).
struct DeviceExercise: Codable, Identifiable, Hashable {
    let exercise_id: Int
    let name: String
    let muscle: String
    let target_sets: Int
    let reps_min: Int
    let reps_max: Int
    let weight: Double?
    var id: Int { exercise_id }
}

struct TodayResponse: Codable {
    let routine: String?
    let exercises: [DeviceExercise]
}

// Una rutina disponible (GET /api/gym/device/routines).
// `group` es opcional: si el servidor no lo manda (backend antiguo) se trata
// como "normal" y la app sigue funcionando en vez de fallar al decodificar.
struct DeviceRoutine: Codable, Identifiable {
    let id: Int
    let name: String
    let today: Bool
    let group: String?  // "normal" | "verano" | nil
}

// Respuesta al registrar una serie (POST /api/gym/device/set).
struct SetResult: Codable {
    let workout_id: Int
    let set_number: Int
    let pr: String?          // "peso" | "1rm" | nil
    let prev_best: Double?   // mejor peso de entrenos anteriores (¿subes hoy?)
    let next_weight: Double? // recomendacion actualizada para la proxima
}
