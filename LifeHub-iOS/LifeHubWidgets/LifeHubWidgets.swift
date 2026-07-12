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

// ── Widget de Comidas ────────────────────────────────────────────────────────
struct MealsView: View {
    let entry: HabitsEntry
    var meals: [Habit] {
        let order = ["desayuno", "comida", "almuerzo", "merienda", "cena"]
        return entry.habits.filter { $0.category == .diet }
            .sorted { a, b in
                (order.firstIndex { a.name.lowercased().contains($0) } ?? 9)
                    < (order.firstIndex { b.name.lowercased().contains($0) } ?? 9)
            }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Comidas", systemImage: "fork.knife")
                .font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
            if meals.isEmpty {
                Text("Sin datos").font(.caption).foregroundStyle(Theme.muted)
            } else {
                ForEach(meals.prefix(4)) { HabitCheckRow(habit: $0) }
            }
            Spacer(minLength: 0)
        }
    }
}

struct MealsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MealsWidget", provider: HabitsProvider()) { entry in
            MealsView(entry: entry).containerBackground(Theme.bg, for: .widget)
        }
        .configurationDisplayName("Comidas")
        .description("Marca tus comidas del día sin abrir la app.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// ── Widget de Rutinas ────────────────────────────────────────────────────────
struct RoutinesView: View {
    let entry: HabitsEntry
    var routines: [Habit] {
        entry.habits.filter { Category.routine.contains($0.category) && $0.due_today }
            .sorted { !$0.done_today && $1.done_today }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Pendiente hoy", systemImage: "checklist")
                .font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
            if routines.isEmpty {
                Text("Todo hecho").font(.caption).foregroundStyle(Theme.muted)
            } else {
                ForEach(routines.prefix(5)) { HabitCheckRow(habit: $0) }
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

// ── Bundle ───────────────────────────────────────────────────────────────────
@main
struct LifeHubWidgetBundle: WidgetBundle {
    var body: some Widget {
        MealsWidget()
        RoutinesWidget()
        StudyWidget()
    }
}
