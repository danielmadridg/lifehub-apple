import SwiftUI

/// Navegación principal: 4 pestañas de uso diario + "Más" (igual que la web).
struct RootView: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView() }
                .tabItem { Label("Hoy", systemImage: "house.fill") }
                .tag(0)

            NavigationStack { GymView() }
                .tabItem { Label("Gym", systemImage: "dumbbell.fill") }
                .tag(1)

            NavigationStack { NutritionView() }
                .tabItem { Label("Comida", systemImage: "fork.knife") }
                .tag(2)

            NavigationStack { FinanceView() }
                .tabItem { Label("Dinero", systemImage: "eurosign.circle.fill") }
                .tag(3)

            NavigationStack { MoreView() }
                .tabItem { Label("Más", systemImage: "square.grid.2x2.fill") }
                .tag(4)
        }
        .background(Theme.bg)
        .onChange(of: tab) { _, _ in Haptics.selection() }
    }
}

struct MoreView: View {
    var body: some View {
        Screen(title: "Más") {
            VStack(spacing: 10) {
                MoreLink(icon: "waveform.path.ecg", label: "Rutinas") { RoutinesView() }
                MoreLink(icon: "checklist", label: "Tareas") { TasksView() }
                MoreLink(icon: "envelope.fill", label: "Correo") { MailView() }
                MoreLink(icon: "calendar", label: "Agenda") { CalendarView() }
                MoreLink(icon: "graduationcap.fill", label: "Estudios") { StudiesView() }
                MoreLink(icon: "gearshape.fill", label: "Ajustes") { SettingsView() }
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
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32)
                Text(label)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            .card()
        }
        .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
    }
}
