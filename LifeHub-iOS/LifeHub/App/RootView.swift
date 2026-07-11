import SwiftUI

/// Navegación principal: 4 pestañas de uso diario + "Más" (igual que la web).
struct RootView: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Hoy", systemImage: "house") }
                .tag(0)

            NavigationStack { GymView() }
                .tabItem { Label("Gym", systemImage: "dumbbell") }
                .tag(1)

            NavigationStack { NutritionView() }
                .tabItem { Label("Comida", systemImage: "fork.knife") }
                .tag(2)

            NavigationStack { FinanceView() }
                .tabItem { Label("Dinero", systemImage: "eurosign.circle") }
                .tag(3)

            NavigationStack { MoreView() }
                .tabItem { Label("Más", systemImage: "square.grid.2x2") }
                .tag(4)
        }
        .background(Theme.bg)
        .font(.sans(17))
        .onChange(of: tab) { _, _ in Haptics.selection() }
        .gesture(
            // Deslizar horizontalmente también cambia de pestaña (además de la
            // barra). Solo cuenta si el gesto es claramente horizontal.
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let dx = value.translation.width, dy = value.translation.height
                    guard abs(dx) > 60, abs(dx) > abs(dy) * 1.8 else { return }
                    if dx < 0 { tab = min(tab + 1, 4) } else { tab = max(tab - 1, 0) }
                }
        )
    }
}

struct MoreView: View {
    var body: some View {
        Screen(title: "Más") {
            VStack(spacing: 10) {
                MoreLink(icon: "checklist.unchecked", label: "Rutinas") { RoutinesView() }
                MoreLink(icon: "checklist", label: "Tareas") { TasksView() }
                MoreLink(icon: "envelope", label: "Correo") { MailView() }
                MoreLink(icon: "calendar", label: "Agenda") { CalendarView() }
                MoreLink(icon: "graduationcap", label: "Estudios") { StudiesView() }
                MoreLink(icon: "gearshape", label: "Ajustes") { SettingsView() }
            }
        }
    }
}

struct MoreLink<Destination: View>: View {
    let icon: String
    let label: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
                .toolbarBackground(Theme.bg, for: .navigationBar)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32)
                Text(label)
                    .font(Theme.dHeadline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.dFootnote)
                    .foregroundStyle(Theme.muted)
            }
            .card()
        }
        .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
    }
}
