import SwiftUI

/// Ajustes: gestión de hábitos, estado de conexiones y sesión.
struct SettingsView: View {
    var body: some View {
        Screen(title: "Ajustes") {
            Text("Todo lo que se edita vive aquí. La app del día a día queda limpia: solo marcar, apuntar y consultar.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)

            SettingsLink(icon: "dumbbell.fill", title: "Rutinas de gym",
                         hint: "Crear y editar rutinas y ejercicios") { RoutineManagerView() }
            SettingsLink(icon: "waveform.path.ecg", title: "Hábitos y comidas",
                         hint: "Crear, editar o pausar tus rutinas diarias") { HabitManagerView() }
            SettingsLink(icon: "cart.fill", title: "Lista de la compra",
                         hint: "Añadir o quitar productos") { ShoppingScreen() }
            SettingsLink(icon: "envelope.fill", title: "Conexiones",
                         hint: "Token de Google y sesión de Epitech") { ConnectionsView() }
        }
    }
}

struct SettingsLink<Destination: View>: View {
    let icon: String
    let title: String
    let hint: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            .card()
        }
        .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
    }
}

/// Lista de la compra como pantalla completa (reutiliza ShoppingView).
struct ShoppingScreen: View {
    var body: some View {
        Screen(title: "Compra") { ShoppingView() }
    }
}

// ── Conexiones (estado + renovar token de Google) ────────────────────────────

struct ConnectionsView: View {
    @State private var status: AuthStatus?
    @State private var opening = false

    var body: some View {
        Screen(title: "Conexiones", refresh: { status = try? await API.shared.authStatus() }) {
            Text("Estado de tus cuentas. Cuando algo caduque, se renueva desde aquí.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)

            if let status {
                VStack(alignment: .leading, spacing: 10) {
                    ConnectionRow(
                        name: "Google · Gmail y Agenda",
                        connected: status.google.connected,
                        detail: status.google.days_left.map { "\($0) días" }
                    )
                    if !status.google.connected {
                        HButton(haptic: Haptics.medium) {
                            Task { await renew() }
                        } label: {
                            Text(opening ? "Abriendo Google…" : "Renovar token")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.black)
                        }
                        .disabled(opening)
                    }
                }
                .card()

                ConnectionRow(
                    name: "Epitech · intra",
                    connected: status.epitech.connected,
                    detail: status.epitech.days_left.map { "~\($0) días" }
                )
                if !status.epitech.connected {
                    Text("La sesión de Epitech necesita login de Microsoft + 2FA en el ordenador. Pídemelo y lo renovamos.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            } else {
                SkeletonList(rows: 2)
            }
        }
        .task { status = try? await API.shared.authStatus() }
    }

    func renew() async {
        opening = true
        defer { opening = false }
        if let r = try? await API.shared.authGoogleURL(), let url = URL(string: r.url) {
            await UIApplication.shared.open(url)
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
