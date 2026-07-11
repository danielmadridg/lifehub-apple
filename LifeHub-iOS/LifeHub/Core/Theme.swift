import SwiftUI

/// Estética de Life Hub: café oscuro + naranja "brasa".
/// Display en serif (New York) — heredera del Fraunces de la web.
enum Theme {
    static let bg = Color(red: 0.086, green: 0.063, blue: 0.051)        // café casi negro
    static let surface = Color(red: 0.125, green: 0.098, blue: 0.078)
    static let surface2 = Color(red: 0.176, green: 0.137, blue: 0.106)
    static let line = Color(red: 0.28, green: 0.23, blue: 0.19).opacity(0.5)
    static let ink = Color(red: 0.95, green: 0.92, blue: 0.88)
    static let muted = Color(red: 0.66, green: 0.60, blue: 0.54)
    static let accent = Color(red: 0.96, green: 0.51, blue: 0.16)       // brasa
    static let good = Color(red: 0.55, green: 0.78, blue: 0.45)
    static let bad = Color(red: 0.87, green: 0.42, blue: 0.36)
}

extension Font {
    /// Titulares con carácter (serif New York), jerarquía dramática.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
}

enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func rigid() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

/// Botón con háptico integrado — respuesta táctil consistente en toda la app.
/// Sustituye a Button cuando quieres el "tic" sutil al pulsar.
struct HButton<Label: View>: View {
    var haptic: () -> Void = Haptics.light
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            haptic()
            action()
        } label: {
            label()
        }
    }
}
