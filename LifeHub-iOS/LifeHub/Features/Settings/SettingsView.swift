import SwiftUI

/// Ajustes: gestión de hábitos, estado de conexiones y sesión.
struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var status: AuthStatus?

    var body: some View {
        Screen(title: "Ajustes", refresh: { status = try? await API.shared.authStatus() }) {
            SectionHeader(title: "Hábitos y comidas")
            NavigationLink {
                HabitManagerView()
            } label: {
                HStack {
                    Label("Gestionar hábitos", systemImage: "slider.horizontal.3")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                .card()
            }

            SectionHeader(title: "Conexiones")
            if let status {
                ConnectionRow(
                    name: "Google (Correo)",
                    connected: status.google.connected,
                    detail: status.google.days_left.map { "\($0) días de token" }
                )
                ConnectionRow(
                    name: "Epitech (Estudios)",
                    connected: status.epitech.connected,
                    detail: status.epitech.days_left.map { "\($0) días de token" }
                )
            } else {
                SkeletonList(rows: 2)
            }

            SectionHeader(title: "Servidor")
            VStack(alignment: .leading, spacing: 4) {
                Text(app.baseURL)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Theme.muted)
                Text("Se cambia al cerrar sesión.")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
            .card()

            Button(role: .destructive) {
                app.logout()
            } label: {
                Text("Cerrar sesión")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Theme.bad)
            }
            .padding(.top, 12)
        }
        .task {
            status = try? await API.shared.authStatus()
        }
    }
}

struct ConnectionRow: View {
    let name: String
    let connected: Bool
    let detail: String?

    var body: some View {
        HStack {
            Circle()
                .fill(connected ? Theme.good : Theme.bad)
                .frame(width: 9, height: 9)
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(connected ? (detail ?? "Conectado") : "Sin conexión")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .card(padding: 13)
    }
}

// ── Gestión de hábitos (CRUD, vive en Ajustes como en la web) ───────────────

struct HabitManagerView: View {
    @State private var habits: [Habit]?
    @State private var error: String?
    @State private var editing: Habit?
    @State private var creating = false

    var body: some View {
        Screen(title: "Hábitos", refresh: { await load() }) {
            if let error {
                ErrorCard(detail: error) { await load() }
            } else if let habits {
                Button {
                    creating = true
                } label: {
                    Label("Nuevo hábito", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.black)
                }

                ForEach(habits) { habit in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(habit.name)
                                .font(.headline)
                                .foregroundStyle(habit.active ? Theme.ink : Theme.muted)
                            Text(habit.category.label)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Toggle("", isOn: .init(
                            get: { habit.active },
                            set: { on in
                                Task {
                                    _ = try? await API.shared.updateHabit(habit.id, ["active": .bool(on)])
                                    await load()
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                    .card(padding: 13)
                    .contextMenu {
                        Button {
                            editing = habit
                        } label: {
                            Label("Editar", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            Task {
                                _ = try? await API.shared.deleteHabit(habit.id)
                                await load()
                            }
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
                }
            } else {
                SkeletonList()
            }
        }
        .task { await load() }
        .sheet(isPresented: $creating) {
            HabitFormSheet(habit: nil) { await load() }
        }
        .sheet(item: $editing) { habit in
            HabitFormSheet(habit: habit) { await load() }
        }
    }

    func load() async {
        do {
            habits = try await API.shared.habits()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Alta/edición de hábito: horas fijas, días de la semana o cada N días.
struct HabitFormSheet: View {
    let habit: Habit?
    let onDone: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category: Category = .custom
    @State private var scheduleType = "daily_times"
    @State private var times = "09:00"
    @State private var intervalDays = 2
    @State private var weekDays: Set<Int> = []

    private let dayNames = ["L", "M", "X", "J", "V", "S", "D"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $name)

                Picker("Categoría", selection: $category) {
                    ForEach(Category.allCases) { c in
                        Text(c.label).tag(c)
                    }
                }

                Picker("Horario", selection: $scheduleType) {
                    Text("Horas fijas").tag("daily_times")
                    Text("Días de la semana").tag("week_days")
                    Text("Cada N días").tag("interval_days")
                }

                switch scheduleType {
                case "interval_days":
                    Stepper("Cada \(intervalDays) días", value: $intervalDays, in: 1...30)
                case "week_days":
                    HStack {
                        ForEach(0..<7, id: \.self) { d in
                            Button(dayNames[d]) {
                                if weekDays.contains(d) { weekDays.remove(d) } else { weekDays.insert(d) }
                            }
                            .buttonStyle(.borderless)
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                weekDays.contains(d) ? Theme.accent : Theme.surface2,
                                in: Circle()
                            )
                            .foregroundStyle(weekDays.contains(d) ? .black : Theme.muted)
                        }
                    }
                    TextField("Horas (09:00, 14:00…)", text: $times)
                default:
                    TextField("Horas (09:00, 14:00…)", text: $times)
                }
            }
            .navigationTitle(habit == nil ? "Nuevo hábito" : "Editar hábito")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(name.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .onAppear { fill() }
        }
        .preferredColorScheme(.dark)
    }

    func fill() {
        guard let habit else { return }
        name = habit.name
        category = habit.category
        scheduleType = habit.schedule_type
        switch habit.schedule {
        case .times(let t): times = t.joined(separator: ", ")
        case .interval(let n): intervalDays = n
        case .week(let w):
            weekDays = Set(w.days)
            times = w.times.joined(separator: ", ")
        }
    }

    func save() async {
        let timeList = times.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }

        let schedule: JSONValue
        switch scheduleType {
        case "interval_days":
            schedule = .int(intervalDays)
        case "week_days":
            schedule = .object([
                "days": .array(weekDays.sorted().map { .int($0) }),
                "times": .array(timeList.map { .string($0) }),
            ])
        default:
            schedule = .array(timeList.map { .string($0) })
        }

        let data: [String: JSONValue] = [
            "name": .string(name),
            "category": .string(category.rawValue),
            "schedule_type": .string(scheduleType),
            "schedule": schedule,
        ]
        if let habit {
            _ = try? await API.shared.updateHabit(habit.id, data)
        } else {
            _ = try? await API.shared.createHabit(data)
        }
        await onDone()
        dismiss()
    }
}
