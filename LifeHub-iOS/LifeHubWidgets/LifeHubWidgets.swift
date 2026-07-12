import WidgetKit
import SwiftUI
import AppIntents

// ── Intent interactivo: marcar/desmarcar un hábito ───────────────────────────
struct ToggleHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Marcar hábito"
    @Parameter(title: "id") var id: Int
    @Parameter(title: "hecho") var done: Bool
    init() {}
    init(id: Int, done: Bool) { self.id = id; self.done = done }
    func perform() async throws -> some IntentResult {
        if done { _ = try? await API.shared.undoDone(id) } else { _ = try? await API.shared.markDone(id) }
        return .result()
    }
}

struct HabitCheckRow: View {
    let habit: Habit
    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ToggleHabitIntent(id: habit.id, done: habit.done_today)) {
                Image(systemName: habit.done_today ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(habit.done_today ? Theme.good : Theme.muted)
            }
            .buttonStyle(.plain)
            Text(habit.name)
                .font(.system(size: 15, weight: .medium))
                .strikethrough(habit.done_today)
                .foregroundStyle(habit.done_today ? Theme.muted : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
    }
}

// ── Barra de macro ───────────────────────────────────────────────────────────
struct MacroBar: View {
    let label: String, value: Double, target: Double, unit: String, tint: Color
    var pct: Double { target > 0 ? min(value / target, 1) : 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface2)
                    Capsule().fill(tint).frame(width: g.size.width * pct)
                }
            }
            .frame(height: 7)
            Text("\(Int(value)) / \(Int(target)) \(unit)")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.muted)
        }
    }
}

// ── COMIDA (mediano, rectangular): macros a la izquierda, ticks a la derecha ─
struct MealsEntry: TimelineEntry {
    let date: Date
    let meals: [Habit]
    let kcal: Double, kcalTarget: Double
    let protein: Double, proteinTarget: Double
}

struct MealsProvider: TimelineProvider {
    func placeholder(in c: Context) -> MealsEntry { MealsEntry(date: .now, meals: [], kcal: 0, kcalTarget: 2500, protein: 0, proteinTarget: 150) }
    func getSnapshot(in c: Context, completion: @escaping (MealsEntry) -> Void) { Task { completion(await fetch()) } }
    func getTimeline(in c: Context, completion: @escaping (Timeline<MealsEntry>) -> Void) {
        Task { completion(Timeline(entries: [await fetch()], policy: .after(Date().addingTimeInterval(900)))) }
    }
    func fetch() async -> MealsEntry {
        async let h = try? API.shared.today()
        async let f = try? API.shared.foodDay()
        async let bw = try? API.shared.gymBodyweight()
        let order = ["desayuno", "comida", "almuerzo", "merienda", "cena"]
        let meals = ((await h) ?? []).filter { $0.category == .diet }
            .sorted { a, b in
                (order.firstIndex { a.name.lowercased().contains($0) } ?? 9)
                    < (order.firstIndex { b.name.lowercased().contains($0) } ?? 9)
            }
        let food = await f
        let weight = (await bw)?.first?.weight ?? Me.fallbackWeight
        return MealsEntry(date: .now, meals: meals,
                          kcal: food?.total_kcal ?? 0, kcalTarget: Double(Me.kcalTarget(weight: weight)),
                          protein: food?.total_protein ?? 0, proteinTarget: Me.proteinTarget(weight: weight))
    }
}

struct MealsView: View {
    let entry: MealsEntry
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Comida").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
                MacroBar(label: "Calorías", value: entry.kcal, target: entry.kcalTarget, unit: "kcal", tint: Theme.accent)
                MacroBar(label: "Proteína", value: entry.protein, target: entry.proteinTarget, unit: "g", tint: Theme.accent2)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider().overlay(Theme.line)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(entry.meals.prefix(4)) { HabitCheckRow(habit: $0) }
                Spacer(minLength: 0)
            }
            .frame(width: 150, alignment: .leading)
        }
    }
}

struct MealsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MealsWidget", provider: MealsProvider()) { entry in
            MealsView(entry: entry).containerBackground(Theme.bg, for: .widget)
        }
        .configurationDisplayName("Comida")
        .description("Macros del día y tus comidas con un toque.")
        .supportedFamilies([.systemMedium])
    }
}

// ── Provider de hábitos de hoy (rutinas) ─────────────────────────────────────
struct HabitsEntry: TimelineEntry { let date: Date; let habits: [Habit] }
struct HabitsProvider: TimelineProvider {
    func placeholder(in c: Context) -> HabitsEntry { HabitsEntry(date: .now, habits: []) }
    func getSnapshot(in c: Context, completion: @escaping (HabitsEntry) -> Void) { Task { completion(await fetch()) } }
    func getTimeline(in c: Context, completion: @escaping (Timeline<HabitsEntry>) -> Void) {
        Task { completion(Timeline(entries: [await fetch()], policy: .after(Date().addingTimeInterval(900)))) }
    }
    func fetch() async -> HabitsEntry { HabitsEntry(date: .now, habits: (try? await API.shared.today()) ?? []) }
}

// ── RUTINAS (pequeño) ────────────────────────────────────────────────────────
struct RoutinesView: View {
    let entry: HabitsEntry
    var all: [Habit] { entry.habits.filter { Category.routine.contains($0.category) } }
    var pending: [Habit] { all.filter { $0.due_today && !$0.done_today } }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Rutinas").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
                Spacer()
                Text("\(all.filter(\.done_today).count)/\(all.count)")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.muted)
            }
            if pending.isEmpty {
                Spacer()
                Text("Todo hecho\npor hoy ✓").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.good)
                Spacer()
            } else {
                ForEach(pending.prefix(4)) { HabitCheckRow(habit: $0) }
                Spacer(minLength: 0)
            }
        }
    }
}

struct RoutinesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RoutinesWidget", provider: HabitsProvider()) { entry in
            RoutinesView(entry: entry).containerBackground(Theme.bg, for: .widget)
        }
        .configurationDisplayName("Rutinas")
        .description("Marca tus rutinas del día.")
        .supportedFamilies([.systemSmall])
    }
}

// ── ENTRENO (pequeño): rutina de hoy + progreso vs último ────────────────────
struct WorkoutEntry: TimelineEntry {
    let date: Date
    let name: String?
    let count: Int
    let deltaKg: Double?
}

struct WorkoutProvider: TimelineProvider {
    func placeholder(in c: Context) -> WorkoutEntry { WorkoutEntry(date: .now, name: nil, count: 0, deltaKg: nil) }
    func getSnapshot(in c: Context, completion: @escaping (WorkoutEntry) -> Void) { Task { completion(await fetch()) } }
    func getTimeline(in c: Context, completion: @escaping (Timeline<WorkoutEntry>) -> Void) {
        Task { completion(Timeline(entries: [await fetch()], policy: .after(Date().addingTimeInterval(3600)))) }
    }
    func fetch() async -> WorkoutEntry {
        async let r = try? API.shared.gymRoutines()
        async let w = try? API.shared.gymWorkouts()
        let routines = (await r) ?? []
        let name = Season.isSummer ? Season.todaySummerRoutine : routines.first { $0.today == true }?.name
        let count = routines.first { $0.name == name }?.exercises.count ?? 0
        let workouts = ((await w) ?? []).sorted { $0.started_at > $1.started_at }
        var delta: Double?
        if workouts.count >= 2 { delta = workouts[0].volume - workouts[1].volume }
        return WorkoutEntry(date: .now, name: name, count: count, deltaKg: delta)
    }
}

struct WorkoutWidgetView: View {
    let entry: WorkoutEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Gym").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
            Spacer(minLength: 0)
            if let name = entry.name {
                Text("HOY TOCA").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
                Text(name).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.ink)
                    .lineLimit(2).minimumScaleFactor(0.7)
                Text("\(entry.count) ejercicios").font(.system(size: 13)).foregroundStyle(Theme.muted)
            } else {
                Text("Descanso").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.ink)
                Text("Hoy no toca").font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            if let d = entry.deltaKg {
                Text(d >= 0 ? "▲ +\(Int(d)) kg vs anterior" : "▼ \(Int(d)) kg vs anterior")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(d >= 0 ? Theme.good : Theme.bad)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }
}

struct WorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WorkoutWidget", provider: WorkoutProvider()) { entry in
            WorkoutWidgetView(entry: entry).containerBackground(Theme.bg, for: .widget)
        }
        .configurationDisplayName("Entreno de hoy")
        .description("Qué toca hoy y tu progreso respecto al último entreno.")
        .supportedFamilies([.systemSmall])
    }
}

// ── CLAUDE (pequeño): % sesión y semanal ─────────────────────────────────────
struct ClaudeEntry: TimelineEntry { let date: Date; let usage: ClaudeUsage? }
struct ClaudeProvider: TimelineProvider {
    func placeholder(in c: Context) -> ClaudeEntry { ClaudeEntry(date: .now, usage: nil) }
    func getSnapshot(in c: Context, completion: @escaping (ClaudeEntry) -> Void) { Task { completion(await fetch()) } }
    func getTimeline(in c: Context, completion: @escaping (Timeline<ClaudeEntry>) -> Void) {
        Task { completion(Timeline(entries: [await fetch()], policy: .after(Date().addingTimeInterval(900)))) }
    }
    func fetch() async -> ClaudeEntry { ClaudeEntry(date: .now, usage: try? await API.shared.claudeUsage()) }
}

struct ClaudeWidgetView: View {
    let entry: ClaudeEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Claude").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
            if let u = entry.usage {
                pct("Sesión", u.session)
                pct("Semanal", u.weekly)
            } else {
                Spacer(); Text("Sin datos").font(.system(size: 15)).foregroundStyle(Theme.muted); Spacer()
            }
            Spacer(minLength: 0)
        }
    }
    @ViewBuilder func pct(_ label: String, _ w: ClaudeUsage.Window?) -> some View {
        if let w {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("\(w.pct)%").font(.system(size: 17, weight: .bold))
                        .foregroundStyle(w.pct >= 90 ? Theme.bad : Theme.ink)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surface2)
                        Capsule().fill(w.pct >= 90 ? Theme.bad : Theme.accent)
                            .frame(width: g.size.width * CGFloat(min(w.pct, 100)) / 100)
                    }
                }
                .frame(height: 6)
            }
        }
    }
}

struct ClaudeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeWidget", provider: ClaudeProvider()) { entry in
            ClaudeWidgetView(entry: entry).containerBackground(Theme.bg, for: .widget)
        }
        .configurationDisplayName("Uso de Claude")
        .description("Uso de sesión y semanal.")
        .supportedFamilies([.systemSmall])
    }
}

// ── ESTUDIOS (grande): texto de la IA ────────────────────────────────────────
struct StudyEntry: TimelineEntry { let date: Date; let text: String }
struct StudyProvider: TimelineProvider {
    func placeholder(in c: Context) -> StudyEntry { StudyEntry(date: .now, text: "…") }
    func getSnapshot(in c: Context, completion: @escaping (StudyEntry) -> Void) { Task { completion(await fetch()) } }
    func getTimeline(in c: Context, completion: @escaping (Timeline<StudyEntry>) -> Void) {
        Task { completion(Timeline(entries: [await fetch()], policy: .after(Date().addingTimeInterval(3600)))) }
    }
    func fetch() async -> StudyEntry {
        StudyEntry(date: .now, text: (try? await API.shared.aiStudies())?.text ?? "Sin novedades de estudios.")
    }
}

struct StudyWidgetView: View {
    let entry: StudyEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Estudios", systemImage: "graduationcap")
                .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.accent)
            Text(entry.text)
                .font(.system(size: 17))
                .foregroundStyle(Theme.ink)
                .lineLimit(nil)
                .minimumScaleFactor(0.9)
            Spacer(minLength: 0)
        }
    }
}

struct StudyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StudyWidget", provider: StudyProvider()) { entry in
            StudyWidgetView(entry: entry).containerBackground(Theme.bg, for: .widget)
        }
        .configurationDisplayName("Estudios · IA")
        .description("El resumen de estudios que genera la IA.")
        .supportedFamilies([.systemLarge])
    }
}

// ── Bundle ───────────────────────────────────────────────────────────────────
@main
struct LifeHubWidgetBundle: WidgetBundle {
    var body: some Widget {
        MealsWidget()
        RoutinesWidget()
        WorkoutWidget()
        ClaudeWidget()
        StudyWidget()
    }
}
