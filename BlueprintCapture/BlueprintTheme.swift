import SwiftUI

// Visual design system for Blueprint Capture
// Centralizes brand colors, gradients, and reusable styles so all screens feel cohesive.
enum BlueprintTheme {
    // Primary brand colors – trustworthy blue palette
    static let primary        = Color(red: 0.12, green: 0.44, blue: 0.98)    // Blueprint Blue
    static let primaryDeep    = Color(red: 0.04, green: 0.20, blue: 0.55)    // Deep Navy
    static let accentAqua     = Color(red: 0.12, green: 0.76, blue: 0.95)
    static let successGreen   = Color(red: 0.18, green: 0.68, blue: 0.43)
    static let warningOrange  = Color(red: 0.98, green: 0.58, blue: 0.20)
    static let errorRed       = Color(red: 0.92, green: 0.20, blue: 0.20)

    // Neutrals
    static let surface        = Color(.secondarySystemBackground)
    static let surfaceElevated = Color(.tertiarySystemBackground)

    // Background gradient for hero/top sections
    static let heroGradient = LinearGradient(
        colors: [primaryDeep.opacity(0.95), primary.opacity(0.85)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Reusable Styles

struct BlueprintPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [BlueprintTheme.primary, BlueprintTheme.primaryDeep], startPoint: .top, endPoint: .bottom))
                    .shadow(color: BlueprintTheme.primary.opacity(configuration.isPressed ? 0.15 : 0.25), radius: configuration.isPressed ? 4 : 10, x: 0, y: configuration.isPressed ? 2 : 8)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct BlueprintSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(BlueprintTheme.primary)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BlueprintTheme.primary.opacity(0.25), lineWidth: 1)
            )
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.02 : 0.06), radius: configuration.isPressed ? 2 : 6, x: 0, y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct BlueprintCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(BlueprintTheme.surface)
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
        )
    }
}

extension View {
    // Applies a subtle top gradient and spacing that works well for onboarding screens
    func blueprintScreenBackground() -> some View {
        self
            .background(
                ZStack(alignment: .top) {
                    Color(.systemBackground)
                        .ignoresSafeArea()
                    BlueprintTheme.heroGradient
                        .frame(height: 140)
                        .ignoresSafeArea(edges: .top)
                        .opacity(0.55)
                }
            )
    }
}


