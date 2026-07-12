import WidgetKit
import SwiftUI
import AppIntents

// ── Intent interactivo: marcar/desmarcar un hábito desde el widget ───────────
struct ToggleHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Marcar hábito"
    @Parameter(title: "id") var id: Int
    @Parameter(title: "hecho") var done: Bool

    init() {}
    init(id: Int, done: Bool) { self.id = id; self.done = done }

    func perform() async throws -> some IntentResult {
        if done { _ = try? await API.shared.undoDone(id) }
        else { _ = try? await API.shared.markDone(id) }
        return .result()
    }
}

// ── Proveedor de hábitos de hoy (comidas y rutinas) ──────────────────────────
struct HabitsEntry: TimelineEntry {
    let date: Date
    let habits: [Habit]
}

struct HabitsProvider: TimelineProvider {
    func placeholder(in context: Context) -> HabitsEntry { HabitsEntry(date: .now, habits: []) }
    func getSnapshot(in context: Context, completion: @escaping (HabitsEntry) -> Void) {
        Task { completion(await fetch()) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitsEntry>) -> Void) {
        Task {
            let entry = await fetch()
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900))))
        }
    }
    func fetch() async -> HabitsEntry {
        let habits = (try? await API.shared.today()) ?? []
        return HabitsEntry(date: .now, habits: habits)
    }
}

// ── Fila con check interactivo ───────────────────────────────────────────────
struct HabitCheckRow: View {
    let habit: Habit
    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ToggleHabitIntent(id: habit.id, done: habit.done_today)) {
                Image(systemName: habit.done_today ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(habit.done_today ? Theme.good : Theme.muted)
            }
            .buttonStyle(.plain)
            Text(habit.name)
                .font(.caption)
                .strikethrough(habit.done_today)
                .foregroundStyle(habit.done_today ? Theme.muted : Theme.ink)
                .lineLimit(1)
            Spacer()
        }
    }
}

// ── Widget de Comidas (macros + checklist) ───────────────────────────────────
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

struct MacroBar: View {
    let label: String, value: Double, target: Double, unit: String, tint: Color
    var pct: Double { target > 0 ? min(value / target, 1) : 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption2).foregroundStyle(Theme.muted)
                Spacer()
                Text("\(Int(value))/\(Int(target)) \(unit)").font(.caption2.monospacedDigit()).foregroundStyle(Theme.muted)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface2)
                    Capsule().fill(tint).frame(width: g.size.width * pct)
                }
            }
            .frame(height: 5)
        }
    }
}

struct MealsView: View {
    let entry: MealsEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Comida", systemImage: "fork.knife")
                    .font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                Spacer()
                Text("\(entry.meals.filter(\.done_today).count)/\(entry.meals.count)")
                    .font(.caption2.weight(.bold)).foregroundStyle(Theme.muted)
            }
            MacroBar(label: "Calorías", value: entry.kcal, target: entry.kcalTarget, unit: "kcal", tint: Theme.accent)
            MacroBar(label: "Proteína", value: entry.protein, target: entry.proteinTarget, unit: "g", tint: Theme.accent2)
            if family != .systemSmall {
                ForEach(entry.meals.prefix(4)) { HabitCheckRow(habit: $0) }
            }
            Spacer(minLength: 0)
        }
    }
}

struct MealsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MealsWidget", provider: MealsProvider()) { entry in
            MealsView(entry: entry).containerBackground(Theme.bg, for: .widget)
        }
        .configurationDisplayName("Comidas")
        .description("Macros del día y marca tus comidas sin abrir la app.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// ── Widget de Rutinas ────────────────────────────────────────────────────────
struct RoutinesView: View {
    let entry: HabitsEntry
    var all: [Habit] { entry.habits.filter { Category.routine.contains($0.category) } }
    var pending: [Habit] { all.filter { $0.due_today && !$0.done_today } }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Rutinas", systemImage: "checklist")
                    .font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                Spacer()
                Text("\(all.filter(\.done_today).count)/\(all.count)")
                    .font(.caption2.weight(.bold)).foregroundStyle(Theme.muted)
            }
            if pending.isEmpty {
                Text("Todo hecho por hoy ✓").font(.caption).foregroundStyle(Theme.good)
            } else {
                ForEach(pending.prefix(5)) { HabitCheckRow(habit: $0) }
            }
            Spacer(minLength: 0)
        }
    }
}

struct RoutinesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RoutinesWidget", provider: HabitsProvider()) { entry in
            RoutinesView(entry: entry).containerBackground(Theme.bg, for: .widget)
        }
        .configurationDisplayName("Rutinas")
        .description("Marca tus rutinas del día sin abrir la app.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// ── Widget de Estudios (texto de la IA) ──────────────────────────────────────
struct StudyEntry: TimelineEntry {
    let date: Date
    let text: String
}

struct StudyProvider: TimelineProvider {
    func placeholder(in context: Context) -> StudyEntry { StudyEntry(date: .now, text: "…") }
    func getSnapshot(in context: Context, completion: @escaping (StudyEntry) -> Void) {
        Task { completion(await fetch()) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StudyEntry>) -> Void) {
        Task {
            let entry = await fetch()
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
        }
    }
    func fetch() async -> StudyEntry {
        let text = (try? await API.shared.aiStudies())?.text
        return StudyEntry(date: .now, text: text ?? "Sin novedades de estudios.")
    }
}

struct StudyView: View {
    let entry: StudyEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Estudios", systemImage: "graduationcap")
                .font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
            Text(entry.text)
                .font(.caption)
                .foregroundStyle(Theme.ink)
                .lineLimit(6)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
    }
}

struct StudyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StudyWidget", provider: StudyProvider()) { entry in
            StudyView(entry: entry).containerBackground(Theme.bg, for: .widget)
        }
        .configurationDisplayName("Estudios · IA")
        .description("El resumen de estudios que genera la IA.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// ── Widget de Próximo entreno ────────────────────────────────────────────────
struct WorkoutEntry: TimelineEntry {
    let date: Date
    let name: String?
    let count: Int
}

struct WorkoutProvider: TimelineProvider {
    func placeholder(in c: Context) -> WorkoutEntry { WorkoutEntry(date: .now, name: nil, count: 0) }
    func getSnapshot(in c: Context, completion: @escaping (WorkoutEntry) -> Void) { Task { completion(await fetch()) } }
    func getTimeline(in c: Context, completion: @escaping (Timeline<WorkoutEntry>) -> Void) {
        Task { completion(Timeline(entries: [await fetch()], policy: .after(Date().addingTimeInterval(3600)))) }
    }
    func fetch() async -> WorkoutEntry {
        let routines = (try? await API.shared.gymRoutines()) ?? []
        let name = Season.isSummer ? Season.todaySummerRoutine : routines.first { $0.today == true }?.name
        let r = routines.first { $0.name == name }
        return WorkoutEntry(date: .now, name: r?.name, count: r?.exercises.count ?? 0)
    }
}

struct WorkoutView: View {
    let entry: WorkoutEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Gimnasio", systemImage: "dumbbell")
                .font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
            Spacer(minLength: 0)
            if let name = entry.name {
                Text("Hoy toca").font(.caption2).foregroundStyle(Theme.muted)
                Text(name).font(.headline).foregroundStyle(Theme.ink).lineLimit(2).minimumScaleFactor(0.8)
                Text("\(entry.count) ejercicios").font(.caption).foregroundStyle(Theme.muted)
            } else {
                Text("Descanso").font(.headline).foregroundStyle(Theme.ink)
                Text("Hoy no toca entreno").font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
    }
}

struct WorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WorkoutWidget", provider: WorkoutProvider()) { entry in
            WorkoutView(entry: entry).containerBackground(Theme.bg, for: .widget)
        }
        .configurationDisplayName("Entreno de hoy")
        .description("Qué toca hoy en el gimnasio.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// ── Widget de Uso de Claude ──────────────────────────────────────────────────
struct ClaudeEntry: TimelineEntry {
    let date: Date
    let usage: ClaudeUsage?
}

struct ClaudeProvider: TimelineProvider {
    func placeholder(in c: Context) -> ClaudeEntry { ClaudeEntry(date: .now, usage: nil) }
    func getSnapshot(in c: Context, completion: @escaping (ClaudeEntry) -> Void) { Task { completion(await fetch()) } }
    func getTimeline(in c: Context, completion: @escaping (Timeline<ClaudeEntry>) -> Void) {
        Task { completion(Timeline(entries: [await fetch()], policy: .after(Date().addingTimeInterval(900)))) }
    }
    func fetch() async -> ClaudeEntry {
        ClaudeEntry(date: .now, usage: try? await API.shared.claudeUsage())
    }
}

struct ClaudeView: View {
    let entry: ClaudeEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Claude", systemImage: "sparkles")
                .font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
            if let u = entry.usage {
                row("Sesión", u.session)
                row("Semanal", u.weekly)
            } else {
                Text("Sin datos").font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
    }
    @ViewBuilder func row(_ label: String, _ w: ClaudeUsage.Window?) -> some View {
        if let w {
            HStack {
                Text(label).font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(tokens(w.tokens)).font(.caption.weight(.semibold)).foregroundStyle(Theme.ink)
                    if let c = countdown(w.reset) {
                        Text(c).font(.caption2).foregroundStyle(Theme.accent)
                    }
                }
            }
        }
    }
    func tokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1_000_000) : "\(n / 1000)K"
    }
    func countdown(_ iso: String?) -> String? {
        guard let d = Fmt.date(iso) else { return nil }
        let s = d.timeIntervalSinceNow
        if s <= 0 { return "reinicio ya" }
        let days = Int(s) / 86400, hours = (Int(s) % 86400) / 3600, mins = (Int(s) % 3600) / 60
        if days > 0 { return "en \(days)d \(hours)h" }
        if hours > 0 { return "en \(hours)h \(mins)m" }
        return "en \(mins)m"
    }
}

struct ClaudeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeWidget", provider: ClaudeProvider()) { entry in
            ClaudeView(entry: entry).containerBackground(Theme.bg, for: .widget)
        }
        .configurationDisplayName("Uso de Claude")
        .description("Uso de sesión y semanal + cuenta atrás.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// ── Bundle ───────────────────────────────────────────────────────────────────
@main
struct LifeHubWidgetBundle: WidgetBundle {
    var body: some Widget {
        MealsWidget()
        RoutinesWidget()
        StudyWidget()
        WorkoutWidget()
        ClaudeWidget()
    }
}
