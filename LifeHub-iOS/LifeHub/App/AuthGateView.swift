import SwiftUI

/// Pantalla de clave única — heredera de AuthGate.tsx.
/// Valida la clave contra /api/today antes de guardarla.
struct AuthGateView: View {
    @EnvironmentObject var app: AppState
    @State private var key = ""
    @State private var server = ""
    @State private var checking = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text("Life Hub")
                    .font(.display(44, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("CENTRO DE MANDO")
                    .font(.caption.weight(.semibold))
                    .tracking(3)
                    .foregroundStyle(Theme.muted)
            }

            VStack(spacing: 12) {
                SecureField("Clave de acceso", text: $key)
                    .textContentType(.password)
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Theme.ink)

                TextField("Servidor", text: $server)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Theme.muted)
                    .font(.footnote)
            }

            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.bad)
            }

            Button {
                Task { await submit() }
            } label: {
                Group {
                    if checking {
                        ProgressView()
                    } else {
                        Text("Entrar").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.black)
            }
            .disabled(key.isEmpty || checking)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Theme.bg)
        .onAppear { server = app.baseURL }
    }

    func submit() async {
        checking = true
        error = nil
        app.baseURL = server.trimmingCharacters(in: .whitespaces)
        API.shared.token = key
        do {
            _ = try await API.shared.today()
            app.login(token: key)
        } catch {
            API.shared.token = ""
            self.error = "Clave o servidor incorrectos"
        }
        checking = false
    }
}
