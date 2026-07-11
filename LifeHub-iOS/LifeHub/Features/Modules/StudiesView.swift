import SwiftUI

/// Estudios (Epitech vía intra-bot): resumen IA, proyectos y actividades
/// activos. Si no hay nada, no se muestra nada (fin de curso = normal).
struct StudiesView: View {
    @State private var overview: StudyOverview?
    @State private var error: String?
    @State private var refreshing = false

    var body: some View {
        Screen(title: "Estudios", refresh: { await load() }) {
            CoachCard { try await API.shared.aiStudies() }

            if let error {
                ErrorCard(detail: error) { await load() }
            } else if let o = overview {
                if o.status == "error" {
                    Text(o.detail ?? "Error")
                        .font(Theme.dSubheadline)
                        .foregroundStyle(Theme.bad)
                        .card()
                } else {
                    if let summary = o.summary, !summary.isEmpty {
                        Text(summary)
                            .font(Theme.dSubheadline)
                            .foregroundStyle(Theme.ink)
                            .card()
                    }

                    if let projects = o.projects, !projects.isEmpty {
                        SectionHeader(title: "Proyectos en curso")
                        ForEach(projects, id: \.title) { p in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.title)
                                    .font(Theme.dHeadline)
                                    .foregroundStyle(Theme.ink)
                                HStack {
                                    if let deadline = p.deadline {
                                        Label(deadline, systemImage: "clock")
                                    }
                                    if let progress = p.progress {
                                        Label(progress, systemImage: "chart.bar.fill")
                                    }
                                }
                                .font(Theme.dCaption)
                                .foregroundStyle(Theme.muted)
                            }
                            .card()
                        }
                    }

                    if let activities = o.activities, !activities.isEmpty {
                        SectionHeader(title: "Próximas actividades")
                        ForEach(activities, id: \.title) { a in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(a.title)
                                    .font(Theme.dHeadline)
                                    .foregroundStyle(Theme.ink)
                                if let start = a.start {
                                    Label(start, systemImage: "calendar")
                                        .font(Theme.dCaption)
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            .card()
                        }
                    }

                    if let notes = o.notes, !notes.isEmpty {
                        SectionHeader(title: "Notas")
                        ForEach(notes, id: \.title) { n in
                            HStack {
                                Text(n.title)
                                    .font(Theme.dSubheadline)
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Text(n.note ?? "—")
                                    .font(Theme.dSubheadline.weight(.bold))
                                    .foregroundStyle(Theme.accent)
                            }
                            .card(padding: 13)
                        }
                    }

                    if (o.projects ?? []).isEmpty && (o.activities ?? []).isEmpty {
                        EmptyState(text: "Nada activo en Epitech ahora mismo.")
                    }

                    Button {
                        Task { await load(refresh: true) }
                    } label: {
                        Label(refreshing ? "Actualizando…" : "Actualizar datos", systemImage: "arrow.clockwise")
                            .font(Theme.dSubheadline.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .disabled(refreshing)
                }
            } else {
                SkeletonList()
            }
        }
        .task { await load() }
    }

    func load(refresh: Bool = false) async {
        if refresh { refreshing = true }
        do {
            overview = try await API.shared.studies(refresh: refresh)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        refreshing = false
    }
}
