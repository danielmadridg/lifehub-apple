import SwiftUI

/// Correo: no leídos importantes de Gmail (proxy cacheado del backend).
struct MailView: View {
    var body: some View {
        Screen(title: "Correo") {
            CoachCard { try await API.shared.aiMail() }

            LoadView {
                try await API.shared.mail()
            } content: { (overview: MailOverview) in
                if overview.status == "error" {
                    Text(overview.detail ?? "Error")
                        .font(.subheadline)
                        .foregroundStyle(Theme.bad)
                        .card()
                } else if (overview.messages ?? []).isEmpty {
                    EmptyState(text: "Bandeja limpia.")
                } else {
                    ForEach(overview.messages ?? [], id: \.subject) { msg in
                        Group {
                            if let link = msg.link, let url = URL(string: link) {
                                Link(destination: url) { MailRow(msg: msg) }
                            } else {
                                MailRow(msg: msg)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct MailRow: View {
    let msg: MailMessage
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(msg.from)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                Spacer()
                Text(Fmt.short(msg.date))
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
            Text(msg.subject)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            Text(msg.snippet)
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
        }
        .card()
    }
}
