import SwiftUI

@main
struct LifeHubApp: App {
    init() {
        API.shared.token = "BpbEXYlKaUh04zTMydiIzmJ0G32TARTR"
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
