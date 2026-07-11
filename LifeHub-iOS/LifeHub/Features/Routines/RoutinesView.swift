import SwiftUI

/// Rutinas y salud: Hoy / Historial (misma estructura que la web).
struct RoutinesView: View {
    @State private var tab = 0

    var body: some View {
        Screen(title: "Rutinas") {
            Picker("", selection: $tab) {
                Text("Hoy").tag(0)
                Text("Historial").tag(1)
            }
            .pickerStyle(.segmented)

            if tab == 0 {
                TodayList(categories: Category.routine)
            } else {
                HistoryList(categories: Category.routine)
            }
        }
    }
}

/// Lista "Hoy": pendientes arriba (el primero destacado), resto en "Al día".
struct TodayList: View {
    let categories: [Category]
    @State private var habits: [Habit]?
    @State private var error: String?

    var filtered: [Habit] { (habits ?? []).filter { categories.contains($0.category) } }
    var due: [Habit] { filtered.filter { $0.due_today } }
    var rest: [Habit] { filtered.filter { !$0.due_today } }

    var body: some View {
        Group {
            if let error {
                ErrorCard(detail: error) { await load() }
            } else if habits == nil {
                SkeletonList()
            } else {
                if filtered.isEmpty {
                    EmptyState(text: "Nada por aquí todavía.")
                }
                if !due.isEmpty {
                    SectionHeader(title: "Pendiente")
                    ForEach(due) { h in
                        HabitRow(habit: h, highlighted: h.id == due.first?.id) { replace($0) }
                    }
                }
                if !rest.isEmpty {
                    SectionHeader(title: "Al día")
                    ForEach(rest) { h in
                        HabitRow(habit: h) { replace($0) }
                    }
                }
            }
        }
        .task { await load() }
    }

    func replace(_ updated: Habit) {
        guard var list = habits, let i = list.firstIndex(where: { $0.id == updated.id }) else { return }
        list[i] = updated
        habits = list
    }

    func load() async {
        do {
            habits = try await API.shared.today()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Fila de hábito con hecho/deshacer optimista y racha.
struct HabitRow: View {
    let habit: Habit
    var highlighted = false
    let onUpdate: (Habit) -> Void

    @State private var busy = false

    var body: some View {
        HStack(spacing: 14) {
            Button {
                Task { await toggle() }
            } label: {
                Image(systemName: habit.done_today ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundStyle(habit.done_today ? Theme.good : Theme.muted)
            }
            .disabled(busy)

            VStack(alignment: .leading, spacing: 3) {
                Text(habit.name)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 8) {
                    if let next = habit.next_time, habit.due_today {
                        Text(next)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(habit.progress_label)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }

            Spacer()

            if habit.streak > 0 {
                Label("\(habit.streak)", systemImage: "flame.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(highlighted ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1.5)
        )
    }

    func toggle() async {
        busy = true
        defer { busy = false }
        do {
            let updated = habit.done_today
                ? try await API.shared.undoDone(habit.id)
                : try await API.shared.markDone(habit.id)
            if !habit.done_today { Haptics.success() } else { Haptics.light() }
            onUpdate(updated)
        } catch {
            Haptics.warning()
        }
    }
}

/// Historial: heatmap de los últimos 28 días por hábito.
struct HabitHistoryRow: Identifiable {
    let habit: Habit
    let doneDays: Set<String>
    var id: Int { habit.id }
}

struct HistoryList: View {
    let categories: [Category]

    var body: some View {
        LoadView {
            let all = try await API.shared.habits()
            let mine = all.filter { categories.contains($0.category) }
            var out: [HabitHistoryRow] = []
            for h in mine {
                let logs = (try? await API.shared.habitHistory(h.id, days: 28)) ?? []
                let days = Set(logs.compactMap { log in
                    Fmt.date(log.done_at).map { $0.formatted(.iso8601.year().month().day()) }
                })
                out.append(HabitHistoryRow(habit: h, doneDays: days))
            }
            return out
        } content: { (rows: [HabitHistoryRow]) in
            if rows.isEmpty {
                EmptyState(text: "Sin historial todavía.")
            }
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 10) {
                    Text(row.habit.name)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Heatmap(doneDays: row.doneDays)
                }
                .card()
            }
        }
    }
}

struct Heatmap: View {
    let doneDays: Set<String>
    let days = 28

    var body: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 5), count: 14)
        LazyVGrid(columns: cols, spacing: 5) {
            ForEach(0..<days, id: \.self) { offset in
                let date = Calendar.current.date(byAdding: .day, value: offset - days + 1, to: .now)!
                let key = date.formatted(.iso8601.year().month().day())
                RoundedRectangle(cornerRadius: 4)
                    .fill(doneDays.contains(key) ? Theme.accent : Theme.surface2)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }
}
