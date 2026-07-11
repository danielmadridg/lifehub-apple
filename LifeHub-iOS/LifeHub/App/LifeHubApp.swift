import SwiftUI

@main
struct LifeHubApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if app.authorized {
                    RootView()
                } else {
                    AuthGateView()
                }
            }
            .environmentObject(app)
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
        }
    }
}

/// Estado global: clave de acceso + URL del servidor.
@MainActor
final class AppState: ObservableObject {
    @Published var authorized: Bool

    @AppStorage("lifehub_base_url") var baseURL: String = "https://dmghub.app"

    init() {
        authorized = !(Keychain.read("lifehub_token") ?? "").isEmpty
        NotificationCenter.default.addObserver(
            forName: API.unauthorizedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.logout() }
        }
    }

    func login(token: String) {
        API.shared.token = token
        authorized = true
        // Precalienta la IA del día para que las tarjetas salgan sin esperar.
        Task { try? await API.shared.aiPrewarm() }
    }

    func logout() {
        API.shared.token = ""
        authorized = false
    }
}
