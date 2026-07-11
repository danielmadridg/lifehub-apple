import SwiftUI

/// Sesión de entreno: plan por ejercicio, recomendación, series, PRs,
/// temporizador de descanso y calculadora de discos.
struct GymTrainView: View {
    @State var workout: GymWorkout
    let onClose: () -> Void

    @State private var prBanner: String?
    @State private var restEnd: Date?
    @State private var finished: GymWorkout?
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let prBanner {
                        Label(prBanner, systemImage: "trophy.fill")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                    }

                    ForEach(workout.plan.indices, id: \.self) { i in
                        ExerciseCard(
                            item: workout.plan[i],
                            workoutId: workout.id,
                            onSetAdded: { set in
                                workout.plan[i].sets.append(set)
                                if let pr = set.pr {
                                    prBanner = "¡PR de \(pr == "peso" ? "peso" : "1RM") en \(workout.plan[i].exercise.name)!"
                                    Haptics.success()
                                }
                                restEnd = Date.now.addingTimeInterval(150) // 2:30
                            },
                            onSetDeleted: { setId in
                                workout.plan[i].sets.removeAll { $0.id == setId }
                            }
                        )
                    }

                    Button {
                        Task { await finish() }
                    } label: {
                        Text("Terminar entreno")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.black)
                    }

                    Button("Descartar entreno", role: .destructive) {
                        confirmDiscard = true
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .background(Theme.bg)
            .navigationTitle(workout.routine_name ?? "Entreno libre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { onClose() }
                }
                ToolbarItem(placement: .principal) {
                    if let restEnd {
                        RestTimer(end: restEnd) { self.restEnd = nil }
                    }
                }
            }
            .confirmationDialog("¿Descartar el entreno?", isPresented: $confirmDiscard) {
                Button("Descartar", role: .destructive) {
                    Task {
                        _ = try? await API.shared.gymDiscardWorkout(workout.id)
                        onClose()
                    }
                }
            }
            .sheet(item: $finished) { w in
                WorkoutSummarySheet(workout: w) { onClose() }
            }
        }
        .preferredColorScheme(.dark)
    }

    func finish() async {
        do {
            finished = try await API.shared.gymFinishWorkout(workout.id)
            Haptics.success()
        } catch {
            Haptics.warning()
        }
    }
}

// ── Temporizador de descanso (2:30 por defecto, +30 s) ─────────────────────

struct RestTimer: View {
    @State var end: Date
    let onDone: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = Int(end.timeIntervalSince(context.date).rounded())
            HStack(spacing: 10) {
                if remaining > 0 {
                    Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Theme.accent)
                    Button("+30s") { end = end.addingTimeInterval(30) }
                        .font(.caption.weight(.bold))
                    Button {
                        onDone()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    Text("¡A la barra!")
                        .font(.headline)
                        .foregroundStyle(Theme.good)
                        .onAppear {
                            Haptics.warning()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { onDone() }
                        }
                }
            }
        }
    }
}

// ── Tarjeta de ejercicio ────────────────────────────────────────────────────

struct ExerciseCard: View {
    let item: GymPlanItem
    let workoutId: Int
    let onSetAdded: (GymSet) -> Void
    let onSetDeleted: (Int) -> Void

    @State private var weight: Double = 0
    @State private var reps: Int = 0
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.exercise.name)
                        .font(.display(19))
                        .foregroundStyle(Theme.ink)
                    Text("\(item.exercise.muscle.capitalized) · \(item.target_sets)×\(item.reps_min)-\(item.reps_max)")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Text("\(item.sets.count)/\(item.target_sets)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(item.sets.count >= item.target_sets ? Theme.good : Theme.muted)
            }

            // Recomendación del algoritmo
            if let w = item.recommendation.weight {
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(w.clean) kg × \(item.recommendation.reps)", systemImage: "target")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text(item.recommendation.note)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    if item.exercise.equipment == "barra" {
                        PlatesHint(total: w)
                    }
                }
            }

            // Última sesión
            if !item.last.isEmpty {
                Text("Última: " + item.last.map { "\($0.weight.clean)×\($0.reps)" }.joined(separator: "  "))
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }

            // Series hechas
            ForEach(item.sets) { set in
                HStack {
                    Text("Serie \(set.set_number)")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text("\(set.weight.clean) kg × \(set.reps)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                    if let pr = set.pr {
                        Text("PR \(pr)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.2), in: Capsule())
                            .foregroundStyle(Theme.accent)
                    }
                    Button {
                        Task {
                            _ = try? await API.shared.gymDeleteSet(workoutId: workoutId, setId: set.id)
                            onSetDeleted(set.id)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.vertical, 2)
            }

            // Registrar serie
            HStack(spacing: 12) {
                Stepper(value: $weight, step: stepFor(item.exercise.equipment)) {
                    Text("\(weight.clean) kg")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                }
                .frame(maxWidth: .infinity)
                Stepper(value: $reps, in: 0...50) {
                    Text("\(reps) reps")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 2)

            Button {
                Task { await addSet() }
            } label: {
                Text("Apuntar serie")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Theme.accent)
            }
            .disabled(saving || reps == 0)
        }
        .card()
        .onAppear {
            // Precarga la sugerencia del algoritmo
            if weight == 0 {
                weight = item.recommendation.weight ?? item.last.first?.weight ?? 0
                reps = item.recommendation.reps
            }
        }
    }

    /// Saltos de SU gym: 1 kg barra/máquina/polea (microdiscos), 2,5 kg mancuernas.
    func stepFor(_ equipment: String) -> Double {
        equipment == "mancuernas" ? 2.5 : 1
    }

    func addSet() async {
        saving = true
        defer { saving = false }
        do {
            let set = try await API.shared.gymAddSet(
                workoutId: workoutId,
                exerciseId: item.exercise.id,
                weight: weight,
                reps: reps
            )
            Haptics.light()
            onSetAdded(set)
        } catch {
            Haptics.warning()
        }
    }
}

/// Hint de discos por lado para ejercicios de barra.
struct PlatesHint: View {
    let total: Double
    var body: some View {
        let result = Me.platesPerSide(total: total)
        if !result.plates.isEmpty {
            Text("Discos/lado: " + result.plates.map(\.clean).joined(separator: " + ")
                 + (result.leftover > 0 ? " (faltan \(result.leftover.clean))" : ""))
                .font(.caption2)
                .foregroundStyle(Theme.muted)
        }
    }
}

// ── Resumen al terminar ─────────────────────────────────────────────────────

struct WorkoutSummarySheet: View {
    let workout: GymWorkout
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Entreno terminado")
                        .font(.display(30, weight: .bold))
                        .foregroundStyle(Theme.ink)

                    if let s = workout.summary {
                        HStack(spacing: 10) {
                            StatTile(icon: "clock.fill", value: "\(s.duration_min)", label: "minutos")
                            StatTile(icon: "scalemass.fill", value: "\(Int(s.volume))", label: "kg movidos")
                        }
                        HStack(spacing: 10) {
                            StatTile(icon: "square.stack.3d.up.fill", value: "\(s.sets)", label: "series")
                            StatTile(icon: "figure.strengthtraining.traditional", value: "\(s.exercises)", label: "ejercicios")
                        }

                        if !s.prs.isEmpty {
                            SectionHeader(title: "Récords")
                            ForEach(s.prs, id: \.exercise) { pr in
                                Label("\(pr.exercise): \(pr.value.clean) (\(pr.kind))", systemImage: "trophy.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                    .card(padding: 12)
                            }
                        }

                        if let vs = s.vs_last {
                            Text(vs.volume_delta >= 0
                                 ? "▲ \(Int(vs.volume_delta)) kg más que el \(Fmt.short(vs.date))"
                                 : "▼ \(Int(-vs.volume_delta)) kg menos que el \(Fmt.short(vs.date))")
                                .font(.subheadline)
                                .foregroundStyle(vs.volume_delta >= 0 ? Theme.good : Theme.bad)
                        }
                    }

                    CoachCard { try await API.shared.aiWorkout(workout.id) }
                }
                .padding(20)
            }
            .background(Theme.bg)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { onClose() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }
}

extension Double {
    /// "80" en vez de "80.0", "2.5" cuando hay decimales.
    var clean: String {
        truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(self))
            : String(format: "%.2f", self).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
}
