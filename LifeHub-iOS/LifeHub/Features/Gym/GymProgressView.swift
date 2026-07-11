import SwiftUI
import Charts

/// Progreso por ejercicio: 1RM estimado y peso top por sesión, PRs y
/// recomendación actual.
struct GymProgressView: View {
    @State private var exercises: [GymExercise] = []
    @State private var selected: GymExercise?
    @State private var progress: GymProgress?
    @State private var error: String?

    var body: some View {
        Screen(title: "Progreso", refresh: { await loadExercises() }) {
            if let error {
                ErrorCard(detail: error) { await loadExercises() }
            } else if exercises.isEmpty {
                SkeletonList()
            } else {
                Menu {
                    ForEach(groupedMuscles, id: \.self) { muscle in
                        Section(muscle.capitalized) {
                            ForEach(exercises.filter { $0.muscle == muscle }) { ex in
                                Button(ex.name) {
                                    selected = ex
                                    Task { await loadProgress(ex) }
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(selected?.name ?? "Elige ejercicio")
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                    .card()
                }

                if let p = progress {
                    HStack(spacing: 10) {
                        StatTile(icon: "trophy.fill", value: "\(p.pr_weight.clean) kg", label: "PR peso")
                        StatTile(icon: "bolt.fill", value: "\(p.pr_1rm.clean) kg", label: "PR 1RM est.")
                    }

                    if let w = p.recommendation.weight {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Próxima sesión: \(w.clean) kg × \(p.recommendation.reps)", systemImage: "target")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                            Text(p.recommendation.note)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        .card()
                    }

                    if p.sessions.count > 1 {
                        SectionHeader(title: "1RM estimado")
                        Chart(p.sessions, id: \.date) { s in
                            LineMark(
                                x: .value("Fecha", Fmt.date(s.date) ?? .now),
                                y: .value("1RM", s.est_1rm)
                            )
                            .foregroundStyle(Theme.accent)
                            .symbol(.circle)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 200)
                        .card()
                    }

                    SectionHeader(title: "Sesiones")
                    ForEach(p.sessions.reversed(), id: \.date) { s in
                        HStack {
                            Text(Fmt.short(s.date))
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(s.top_weight.clean)×\(s.top_reps) · 1RM \(s.est_1rm.clean) · \(Int(s.volume)) kg")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        .card(padding: 12)
                    }
                }
            }
        }
        .task { await loadExercises() }
    }

    var groupedMuscles: [String] {
        Array(Set(exercises.map(\.muscle))).sorted()
    }

    func loadExercises() async {
        do {
            exercises = try await API.shared.gymExercises()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadProgress(_ ex: GymExercise) async {
        progress = nil
        progress = try? await API.shared.gymProgress(ex.id)
    }
}
