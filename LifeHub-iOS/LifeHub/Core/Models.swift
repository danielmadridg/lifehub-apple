import Foundation

// Los nombres de propiedad van en snake_case a propósito: son un espejo 1:1
// de los JSON del backend (misma fuente de verdad que frontend/src/types.ts).

// ── Hábitos ─────────────────────────────────────────────────────────────────

enum Category: String, Codable, CaseIterable, Identifiable {
    case water, medicine, exercise, sleep, chore, custom, diet
    var id: String { rawValue }

    var label: String {
        switch self {
        case .water: return "Agua"
        case .medicine: return "Medicina"
        case .exercise: return "Ejercicio"
        case .sleep: return "Sueño"
        case .chore: return "Tarea doméstica"
        case .custom: return "Rutina"
        case .diet: return "Comida"
        }
    }

    static let routine: [Category] = [.water, .medicine, .exercise, .sleep, .chore, .custom]
    static let nutrition: [Category] = [.diet]
}

struct WeekSchedule: Codable, Hashable {
    var days: [Int]      // 0-6, lunes=0 (weekday() de Python)
    var times: [String]
}

enum ScheduleValue: Codable, Hashable {
    case times([String])       // daily_times
    case interval(Int)         // interval_days
    case week(WeekSchedule)    // week_days

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Int.self) { self = .interval(n); return }
        if let t = try? c.decode([String].self) { self = .times(t); return }
        self = .week(try c.decode(WeekSchedule.self))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .times(let t): try c.encode(t)
        case .interval(let n): try c.encode(n)
        case .week(let w): try c.encode(w)
        }
    }
}

struct Habit: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    var category: Category
    var schedule_type: String
    var schedule: ScheduleValue
    var active: Bool
    var streak: Int
    var done_today: Bool
    var due_today: Bool
    var next_time: String?
    var progress_label: String
    var last_done: String?
}

struct HabitLog: Codable, Identifiable, Hashable {
    let id: Int
    let habit_id: Int
    let done_at: String
    let note: String?
}

// ── Estudios / Correo / Agenda ──────────────────────────────────────────────

struct StudyProject: Codable, Hashable {
    let title: String
    let deadline: String?
    let progress: String?
    let link: String?
}

struct StudyActivity: Codable, Hashable {
    let title: String
    let module: String?
    let start: String?
    let register_deadline: String?
    let link: String?
}

struct StudyNote: Codable, Hashable {
    let title: String
    let note: String?
}

struct StudyOverview: Codable {
    let status: String
    let detail: String?
    let fetched_at: String?
    let summary: String?
    let projects: [StudyProject]?
    let activities: [StudyActivity]?
    let notes: [StudyNote]?
}

struct MailMessage: Codable, Hashable {
    let subject: String
    let from: String
    let snippet: String
    let date: String?
    let link: String?
}

struct MailOverview: Codable {
    let status: String
    let detail: String?
    let messages: [MailMessage]?
}

struct CalendarEvent: Codable, Hashable {
    let title: String
    let start: String?
    let end: String?
    let location: String?
    let link: String?
}

struct CalendarOverview: Codable {
    let status: String
    let detail: String?
    let events: [CalendarEvent]?
}

// ── Gym ─────────────────────────────────────────────────────────────────────

struct GymExercise: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let muscle: String
    let equipment: String
    let custom: Bool
}

struct GymRoutineExercise: Codable, Hashable {
    let exercise_id: Int
    let name: String
    let muscle: String
    let equipment: String
    let sets: Int
    let reps_min: Int
    let reps_max: Int
}

struct GymRoutine: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let today: Bool?
    let group: String?   // "normal" | "verano"
    let exercises: [GymRoutineExercise]
}

struct RoutineModeResponse: Codable {
    let mode: String     // "normal" | "summer"
}

struct GymSet: Codable, Identifiable, Hashable {
    let id: Int
    let exercise_id: Int
    let set_number: Int
    let weight: Double
    let reps: Int
    let pr: String?          // "peso" | "1rm" | nil
}

struct GymRecommendation: Codable, Hashable {
    let weight: Double?
    let reps: Int
    let note: String
}

struct LastSet: Codable, Hashable {
    let weight: Double
    let reps: Int
}

struct GymPlanItem: Codable, Hashable {
    let exercise: GymExercise
    let target_sets: Int
    let reps_min: Int
    let reps_max: Int
    let recommendation: GymRecommendation
    let last: [LastSet]
    var sets: [GymSet]
}

struct WorkoutPR: Codable, Hashable {
    let exercise: String
    let kind: String
    let value: Double
}

struct WorkoutVsLast: Codable, Hashable {
    let date: String
    let last_volume: Double
    let volume_delta: Double
}

struct WorkoutSummary: Codable, Hashable {
    let duration_min: Int
    let volume: Double
    let sets: Int
    let exercises: Int
    let prs: [WorkoutPR]
    let vs_last: WorkoutVsLast?
}

struct GymWorkout: Codable, Identifiable {
    let id: Int
    let routine_id: Int?
    let routine_name: String?
    let started_at: String
    let finished_at: String?
    var plan: [GymPlanItem]
    let summary: WorkoutSummary?
}

struct GymWorkoutSummary: Codable, Identifiable, Hashable {
    let id: Int
    let started_at: String
    let finished_at: String
    let routine_name: String?
    let exercises: Int
    let sets: Int
    let volume: Double
    let duration_min: Int
}

struct GymProgressSession: Codable, Hashable {
    let date: String
    let top_weight: Double
    let top_reps: Int
    let est_1rm: Double
    let volume: Double
    let sets: Int
}

struct GymProgress: Codable {
    let exercise: GymExercise
    let sessions: [GymProgressSession]
    let pr_weight: Double
    let pr_1rm: Double
    let recommendation: GymRecommendation
}

struct MuscleWeek: Codable, Hashable {
    let muscle: String
    let sets: Int
    let volume: Double
}

struct WeeklyStats: Codable {
    let muscles: [MuscleWeek]
    let total_sets: Int
}

struct BodyWeightEntry: Codable, Identifiable, Hashable {
    let id: Int
    let at: String
    let weight: Double
}

struct MeasureEntry: Codable, Identifiable, Hashable {
    let id: Int
    let at: String
    let value: Double
}

typealias Measures = [String: [MeasureEntry]]

struct ProgressPhotoItem: Codable, Identifiable, Hashable {
    let id: Int
    let at: String
    let url: String
    let note: String?
}

struct RecommendationResponse: Codable {
    let recommendation: GymRecommendation
    let last: [LastSet]
}

// ── Comida / Dieta ──────────────────────────────────────────────────────────

struct FoodItem: Codable, Identifiable, Hashable {
    let id: Int
    let at: String
    let name: String
    let kcal: Double
    let protein: Double
}

struct FoodDay: Codable {
    let items: [FoodItem]
    let total_kcal: Double
    let total_protein: Double
}

struct ShopItem: Codable, Identifiable, Hashable {
    let id: Int
    let text: String
    let done: Bool
}

struct DietDay: Codable, Hashable {
    let weekday: String
    let is_today: Bool
    let breakfast: String
    let lunch: String
    let snack: String
    let dinner: String
}

struct DishMacros: Codable, Hashable {
    let kcal: Double
    let protein: Double
}

struct DietPlan: Codable {
    let days: [DietDay]
    let macros: [String: DishMacros]
}

struct HealthDay: Codable, Hashable {
    let day: String
    let steps: Int?
    let sleep_hours: Double?
    let resting_hr: Int?
    let active_kcal: Int?
}

// ── Tareas / Notas ──────────────────────────────────────────────────────────

struct TaskItem: Codable, Identifiable, Hashable {
    let id: Int
    var text: String
    var done: Bool
    var due: String?
    let created_at: String
    let done_at: String?
}

struct NoteItem: Codable, Identifiable, Hashable {
    let id: Int
    let text: String
    let created_at: String
}

// ── Finanzas ────────────────────────────────────────────────────────────────

struct PortfolioPosition: Codable, Hashable {
    let symbol: String
    let qty: Double
    let price: Double
    let value: Double
    let pnl: Double?
    let pnl_pct: Double?
    let day_pct: Double
}

struct PortfolioOverview: Codable {
    let status: String
    let detail: String?
    let currency: String?
    let equity: Double?
    let cash: Double?
    let day_change: Double?
    let day_change_pct: Double?
    let positions: [PortfolioPosition]?
}

struct FinancePoint: Codable, Hashable {
    let date: String
    let alpaca_usd: Double
    let bitvavo_eur: Double
    let total_eur: Double?
}

struct FinanceSummary: Codable {
    let status: String
    let detail: String?
    let rate: Double?
    let alpaca_usd: Double?
    let alpaca_eur: Double?
    let bitvavo_eur: Double?
    let total_eur: Double?
    let day_change_pct: Double?
    let history: [FinancePoint]
}

// ── Varios ──────────────────────────────────────────────────────────────────

struct AIText: Codable {
    let text: String?
}

struct StatusResponse: Codable {
    let status: String
}

struct GoogleURLResponse: Codable {
    let url: String
}

// Uso de Claude (lo sube un script del Mac; ver /api/claude/usage).
struct ClaudeUsage: Codable {
    struct Window: Codable {
        let pct: Int
        let reset: String?
    }
    let session: Window?
    let weekly: Window?
    let updated: String?
}

struct AuthStatus: Codable {
    struct Google: Codable {
        let authorized_at: String?
        let days_left: Int?
        let production: Bool?
        let connected: Bool
    }
    struct Epitech: Codable {
        let connected: Bool
        let days_left: Int?
        let expires_at: String?
    }
    let google: Google
    let epitech: Epitech
}
