import SwiftUI

/// Agenda: calendario del iPhone vía iCloud CalDAV (próximos 30 días).
struct CalendarView: View {
    var body: some View {
        Screen(title: "Agenda") {
            LoadView {
                try await API.shared.calendar()
            } content: { (overview: CalendarOverview) in
                if overview.status == "error" {
                    Text(overview.detail ?? "Error")
                        .font(Theme.dSubheadline)
                        .foregroundStyle(Theme.bad)
                        .card()
                } else if (overview.events ?? []).isEmpty {
                    EmptyState(text: "Sin eventos próximos.")
                } else {
                    ForEach(overview.events ?? [], id: \.title) { event in
                        HStack(spacing: 14) {
                            VStack(spacing: 2) {
                                Text(Fmt.short(event.start))
                                    .font(Theme.dCaption.weight(.bold))
                                    .foregroundStyle(Theme.accent)
                                Text(Fmt.time(event.start))
                                    .font(Theme.dCaption2)
                                    .foregroundStyle(Theme.muted)
                            }
                            .frame(width: 64)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(Theme.dHeadline)
                                    .foregroundStyle(Theme.ink)
                                if let loc = event.location, !loc.isEmpty {
                                    Label(loc, systemImage: "mappin")
                                        .font(Theme.dCaption)
                                        .foregroundStyle(Theme.muted)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .card()
                    }
                }
            }
        }
    }
}
