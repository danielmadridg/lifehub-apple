import SwiftUI

/// Gym: entreno activo, rutina de hoy, historial y accesos a Progreso/Salud.
struct GymView: View {
    @State private var active: GymWorkout?
    @State private var routines: [GymRoutine] = []
    @State private var workouts: [GymWorkoutSummary] = []
    @State private var weekly: WeeklyStats?
    @State private var error: String?
    @State private var loaded = false
    @State private var training: GymWorkout?

    var body: some View {
        Screen(title: "Gym", refresh: { await load() }) {
            if let error {
                ErrorCard(detail: error) { await load() }
            } else if !loaded {
                SkeletonList()
            } else {
                // Entreno a medias → continuar
                if let active {
                    Button {
                        training = active
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Entreno en curso")
                                    .font(.headline)
                                    .foregroundStyle(.black)
                                Text(active.routine_name ?? "Libre")
                                    .font(.caption)
                                    .foregroundStyle(.black.opacity(0.7))
                            }
                            Spacer()
                            Image(systemName: "play.fill")
                                .foregroundStyle(.black)
                        }
                        .padding(16)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }

                SectionHeader(title: "Rutinas")
                ForEach(routines) { routine in
                    RoutineCard(routine: routine) {
                        Task { await start(routine: routine) }
                    }
                }
                Button {
                    Task { await start(routine: nil) }
                } label: {
                    Label("Entreno libre", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Theme.accent)
                }

                HStack(spacing: 10) {
                    NavigationLink {
                        GymProgressView()
                    } label: {
                        Label("Progreso", systemImage: "chart.line.uptrend.xyaxis")
                            .gymChipStyle()
                    }
                    NavigationLink {
                        GymHealthView()
                    } label: {
                        Label("Salud", systemImage: "heart.fill")
                            .gymChipStyle()
                    }
                }

                if let weekly, !weekly.muscles.isEmpty {
                    SectionHeader(title: "Esta semana · \(weekly.total_sets) series")
                    VStack(spacing: 8) {
                        ForEach(weekly.muscles, id: \.muscle) { m in
                            HStack {
                                Text(m.muscle.capitalized)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(m.sets) series · \(Int(m.volume)) kg")
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .card()
                }

                if !workouts.isEmpty {
                    SectionHeader(title: "Últimos entrenos")
                    ForEach(workouts.prefix(10)) { w in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(w.routine_name ?? "Libre")
                                    .font(.headline)
                                    .foregroundStyle(Theme.ink)
                                Text(Fmt.short(w.started_at))
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text("\(w.sets) series · \(Int(w.volume)) kg · \(w.duration_min) min")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        .card(padding: 13)
                    }
                }
            }
        }
        .task { await load() }
        .fullScreenCover(item: $training) { workout in
            GymTrainView(workout: workout) {
                training = nil
                Task { await load() }
            }
        }
    }

    func start(routine: GymRoutine?) async {
        do {
            training = try await API.shared.gymStartWorkout(routineId: routine?.id)
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func load() async {
        do {
            async let a = API.shared.gymActiveWorkout()
            async let r = API.shared.gymRoutines()
            async let w = API.shared.gymWorkouts()
            async let s = API.shared.gymWeeklyStats()
            active = try await a
            routines = try await r
            workouts = try await w
            weekly = try? await s
            error = nil
            loaded = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct RoutineCard: View {
    let routine: GymRoutine
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(routine.name)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                if routine.today == true {
                    Text("HOY")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.accent.opacity(0.15), in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
                Spacer()
                Button(action: onStart) {
                    Text("Empezar")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(.black)
                }
            }
            Text(routine.exercises.map(\.name).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(routine.today == true ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1.5)
        )
    }
}

private extension View {
    func gymChipStyle() -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
            .foregroundStyle(Theme.ink)
    }
}
