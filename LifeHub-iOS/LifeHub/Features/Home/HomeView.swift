import SwiftUI

/// Inicio: saludo, coach IA del día y resumen rápido de cada módulo.
struct HomeView: View {
    @State private var habits: [Habit] = []
    @State private var food: FoodDay?
    @State private var tasks: [TaskItem] = []
    @State private var weight = Me.fallbackWeight

    var pendingHabits: [Habit] { habits.filter { $0.due_today } }
    var pendingTasks: [TaskItem] { tasks.filter { !$0.done } }

    var body: some View {
        Screen(title: greeting, refresh: { await load() }) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .padding(.top, -8)

            CoachCard { try await API.shared.aiToday() }

            // Rutinas pendientes de hoy (marcables desde aquí)
            if !pendingHabits.isEmpty {
                SectionHeader(title: "Pendiente ahora")
                ForEach(pendingHabits.prefix(4)) { habit in
                    HabitRow(habit: habit) { updated in
                        replace(updated)
                    }
                }
            }

            SectionHeader(title: "Resumen")
            HStack(spacing: 10) {
                StatTile(
                    icon: "flame.fill",
                    value: food.map { "\(Int($0.total_kcal))" } ?? "—",
                    label: "de \(Me.kcalTarget(weight: weight)) kcal"
                )
                StatTile(
                    icon: "fish.fill",
                    value: food.map { "\(Int($0.total_protein)) g" } ?? "—",
                    label: "de \(Int(Me.proteinTarget(weight: weight))) g prote"
                )
            }
            HStack(spacing: 10) {
                StatTile(
                    icon: "checklist",
                    value: "\(pendingTasks.count)",
                    label: pendingTasks.count == 1 ? "tarea pendiente" : "tareas pendientes"
                )
                StatTile(
                    icon: "waveform.path.ecg",
                    value: "\(habits.filter(\.done_today).count)/\(habits.count)",
                    label: "rutinas hechas"
                )
            }
        }
        .task { await load() }
    }

    var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 6..<13: return "Buenos días"
        case 13..<21: return "Buenas tardes"
        default: return "Buenas noches"
        }
    }

    func replace(_ updated: Habit) {
        if let i = habits.firstIndex(where: { $0.id == updated.id }) {
            habits[i] = updated
        }
    }

    func load() async {
        async let h = try? API.shared.today()
        async let f = try? API.shared.foodDay()
        async let t = try? API.shared.tasks()
        async let bw = try? API.shared.gymBodyweight()
        habits = await h ?? []
        food = await f
        tasks = await t ?? []
        if let last = await bw?.first?.weight { weight = last }
    }
}

struct StatTile: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(Theme.accent)
            Text(value)
                .font(.display(26, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .card(padding: 14)
    }
}
