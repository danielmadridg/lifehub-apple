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
        if done {
            _ = try? await API.shared.undoDone(id)
            // Si es una comida, quita también sus calorías del resumen.
            if let dish = await Self.dishFor(id),
               let food = try? await API.shared.foodDay(),
               let item = food.items.last(where: { $0.name == dish }) {
                _ = try? await API.shared.removeFood(item.id)
            }
        } else {
            _ = try? await API.shared.markDone(id)
            // Si es una comida, suma sus calorías al resumen (registra el plato).
            if let dish = await Self.dishFor(id) { _ = try? await API.shared.dietLogMeal(dish) }
        }
        return .result()
    }

    /// Plato de hoy que corresponde al hábito de comida (nil si no es comida).
    static func dishFor(_ id: Int) async -> String? {
        guard let habits = try? await API.shared.today(),
              let h = habits.first(where: { $0.id == id }), h.category == .diet,
              let plan = try? await API.shared.dietPlan(),
              let day = plan.days.first(where: { $0.is_today }) else { return nil }
        let n = h.name.lowercased()
        if n.contains("desayuno") { return day.breakfast }
        if n.contains("merienda") { return day.snack }
        if n.contains("cena") { return day.dinner }
        if n.contains("comida") || n.contains("almuerzo") { return day.lunch }
        return nil
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
        StaticConfiguration(kind: "MealsWidgetV2", provider: MealsProvider()) { entry in
            MealsView(entry: entry).containerBackground(Theme.bg, for: .widget)
                .widgetURL(URL(string: "lifehub://open?m=nutrition"))
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
                .widgetURL(URL(string: "lifehub://open?m=routines"))
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
        if workouts.count >= 2, workouts[1].volume > 0 {
            delta = (workouts[0].volume - workouts[1].volume) / workouts[1].volume * 100
        }
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
                Text(d >= 0 ? "▲ +\(Int(d.rounded()))% vs anterior" : "▼ \(Int(d.rounded()))% vs anterior")
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
                .widgetURL(URL(string: "lifehub://open?m=gym"))
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
                .widgetURL(URL(string: "lifehub://open?m=studies"))
        }
        .configurationDisplayName("Uso de Claude")
        .description("Uso de sesión y semanal.")
        .supportedFamilies([.systemSmall])
    }
}

// ── ESTUDIOS (mediano): mismo texto que la pestaña (studies summary) ─────────
struct StudyEntry: TimelineEntry { let date: Date; let text: String }
struct StudyProvider: TimelineProvider {
    func placeholder(in c: Context) -> StudyEntry { StudyEntry(date: .now, text: "…") }
    func getSnapshot(in c: Context, completion: @escaping (StudyEntry) -> Void) { Task { completion(await fetch()) } }
    func getTimeline(in c: Context, completion: @escaping (Timeline<StudyEntry>) -> Void) {
        Task { completion(Timeline(entries: [await fetch()], policy: .after(Date().addingTimeInterval(3600)))) }
    }
    func fetch() async -> StudyEntry {
        // Mismo texto que muestra la pestaña Estudios (summary de /api/studies).
        let s = try? await API.shared.studies()
        var text = s?.summary
        if (text ?? "").isEmpty { text = (try? await API.shared.aiStudies())?.text }
        return StudyEntry(date: .now, text: (text ?? "").isEmpty ? "Sin novedades de estudios." : text!)
    }
}

struct StudyWidgetView: View {
    let entry: StudyEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Estudios", systemImage: "graduationcap")
                .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accent)
            Text(entry.text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
    }
}

struct StudyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StudyWidget", provider: StudyProvider()) { entry in
            StudyWidgetView(entry: entry).containerBackground(Theme.bg, for: .widget)
                .widgetURL(URL(string: "lifehub://open?m=studies"))
        }
        .configurationDisplayName("Estudios · IA")
        .description("El resumen de estudios que genera la IA.")
        .supportedFamilies([.systemMedium])
    }
}

// ── AGENDA (pequeño): ¿algo hoy? ─────────────────────────────────────────────
struct AgendaEntry: TimelineEntry { let date: Date; let events: [CalendarEvent] }
struct AgendaProvider: TimelineProvider {
    func placeholder(in c: Context) -> AgendaEntry { AgendaEntry(date: .now, events: []) }
    func getSnapshot(in c: Context, completion: @escaping (AgendaEntry) -> Void) { Task { completion(await fetch()) } }
    func getTimeline(in c: Context, completion: @escaping (Timeline<AgendaEntry>) -> Void) {
        Task { completion(Timeline(entries: [await fetch()], policy: .after(Date().addingTimeInterval(1800)))) }
    }
    func fetch() async -> AgendaEntry {
        let cal = Calendar.current
        let all = (try? await API.shared.calendar())?.events ?? []
        let today = all.filter { e in
            guard let d = Fmt.date(e.start) else { return false }
            return cal.isDateInToday(d)
        }.sorted { (Fmt.date($0.start) ?? .distantFuture) < (Fmt.date($1.start) ?? .distantFuture) }
        return AgendaEntry(date: .now, events: today)
    }
}

struct AgendaWidgetView: View {
    let entry: AgendaEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agenda").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
            if entry.events.isEmpty {
                Spacer()
                Text("Nada hoy").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.ink)
                Text("día libre").font(.system(size: 13)).foregroundStyle(Theme.muted)
                Spacer()
            } else {
                Text("\(entry.events.count) \(entry.events.count == 1 ? "evento" : "eventos") hoy")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
                ForEach(entry.events.prefix(3), id: \.self) { e in
                    HStack(spacing: 6) {
                        Text(time(e.start)).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accent)
                            .frame(width: 44, alignment: .leading)
                        Text(e.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
                            .lineLimit(1).minimumScaleFactor(0.85)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
    func time(_ iso: String?) -> String {
        guard let iso, iso.contains("T"), let d = Fmt.date(iso) else { return "todo" }
        return d.formatted(.dateTime.hour().minute())
    }
}

struct AgendaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AgendaWidget", provider: AgendaProvider()) { entry in
            AgendaWidgetView(entry: entry).containerBackground(Theme.bg, for: .widget)
                .widgetURL(URL(string: "lifehub://open?m=calendar"))
        }
        .configurationDisplayName("Agenda")
        .description("Si tienes algo hoy.")
        .supportedFamilies([.systemSmall])
    }
}

// ── PANTALLA DE BLOQUEO ──────────────────────────────────────────────────────
struct CreatineLockView: View {
    let entry: HabitsEntry
    @Environment(\.widgetFamily) private var family
    var c: Habit? { entry.habits.first { $0.name.lowercased().contains("creatina") } }
    var body: some View {
        if let c {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Button(intent: ToggleHabitIntent(id: c.id, done: c.done_today)) {
                        Image(systemName: c.done_today ? "checkmark" : "pills.fill").font(.title2)
                    }.buttonStyle(.plain)
                }
            case .accessoryInline:
                Label(c.done_today ? "Creatina ✓" : "Creatina", systemImage: "pills.fill")
            default:
                HStack {
                    Button(intent: ToggleHabitIntent(id: c.id, done: c.done_today)) {
                        Image(systemName: c.done_today ? "checkmark.circle.fill" : "circle").font(.title3)
                    }.buttonStyle(.plain)
                    Text(c.done_today ? "Creatina hecha" : "Creatina").font(.headline)
                    Spacer()
                }
            }
        } else {
            Label("Creatina", systemImage: "pills.fill")
        }
    }
}

struct CreatineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CreatineLock", provider: HabitsProvider()) { entry in
            CreatineLockView(entry: entry)
        }
        .configurationDisplayName("Creatina")
        .description("Marca la creatina desde la pantalla de bloqueo.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct MealsLockView: View {
    let entry: MealsEntry
    var next: Habit? { entry.meals.first { !$0.done_today } }
    var done: Int { entry.meals.filter(\.done_today).count }
    var body: some View {
        if let n = next {
            HStack(spacing: 8) {
                Button(intent: ToggleHabitIntent(id: n.id, done: false)) {
                    Image(systemName: "circle").font(.title3)
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Marcar comida (\(done)/\(entry.meals.count))").font(.caption2)
                    Text(n.name).font(.headline).lineLimit(1)
                }
                Spacer()
            }
        } else {
            Label("Comidas al día ✓", systemImage: "fork.knife")
        }
    }
}

struct MealsLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MealsLock", provider: MealsProvider()) { entry in
            MealsLockView(entry: entry)
        }
        .configurationDisplayName("Comida (bloqueo)")
        .description("Marca la siguiente comida desde la pantalla de bloqueo.")
        .supportedFamilies([.accessoryRectangular])
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
        AgendaWidget()
        StudyWidget()
        CreatineWidget()
        MealsLockWidget()
    }
}
