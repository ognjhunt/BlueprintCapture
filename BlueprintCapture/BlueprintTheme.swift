import SwiftUI

/// Visual design system for Blueprint Capture
/// Clean, minimal styling inspired by Uber/DoorDash
enum BlueprintTheme {
    // MARK: - Primary Colors
    static let primary = Color(red: 0.12, green: 0.44, blue: 0.98)       // Blueprint Blue
    static let primaryDeep = Color(red: 0.04, green: 0.20, blue: 0.55)   // Deep Navy
    static let brandTeal = Color(red: 0.32, green: 0.93, blue: 0.84)     // Teal accent
    static let accentAqua = Color(red: 0.40, green: 0.85, blue: 0.90)    // Aqua accent

    // MARK: - Semantic Colors
    static let successGreen = Color(red: 0.18, green: 0.68, blue: 0.43)
    static let warningOrange = Color(red: 0.98, green: 0.58, blue: 0.20)
    static let errorRed = Color(red: 0.92, green: 0.20, blue: 0.20)

    // MARK: - Background Colors
    static let bgDark = Color(red: 0.06, green: 0.08, blue: 0.12)
    static let bgDarker = Color(red: 0.03, green: 0.05, blue: 0.09)
    static let surface = Color(.secondarySystemBackground)
    static let surfaceElevated = Color(.tertiarySystemBackground)

    // MARK: - Gradients (used sparingly)
    static let onboardingGradient = LinearGradient(
        colors: [bgDarker, Color(red: 0.05, green: 0.10, blue: 0.18)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGradient = LinearGradient(
        colors: [primary.opacity(0.9), brandTeal.opacity(0.7)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let reservedGradient = LinearGradient(
        colors: [primary, primaryDeep],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Button Styles

struct BlueprintPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(BlueprintTheme.primary)
            )
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct BlueprintSuccessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(BlueprintTheme.successGreen)
            )
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
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
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - View Extensions

extension View {
    /// Dark app background with subtle brand accent
    func blueprintAppBackground() -> some View {
        self.background(
            ZStack {
                LinearGradient(
                    colors: [BlueprintTheme.bgDarker, BlueprintTheme.bgDark],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                Circle()
                    .fill(BlueprintTheme.primary.opacity(0.08))
                    .frame(width: 400, height: 400)
                    .blur(radius: 120)
                    .offset(x: -150, y: -300)

                Circle()
                    .fill(BlueprintTheme.brandTeal.opacity(0.06))
                    .frame(width: 300, height: 300)
                    .blur(radius: 100)
                    .offset(x: 180, y: 400)
            }
        )
    }

    /// Background for onboarding screens
    func blueprintOnboardingBackground() -> some View {
        self.background(
            ZStack {
                BlueprintTheme.onboardingGradient
                    .ignoresSafeArea()

                Circle()
                    .fill(BlueprintTheme.primary.opacity(0.12))
                    .frame(width: 400, height: 400)
                    .blur(radius: 120)
                    .offset(x: -160, y: -280)

                Circle()
                    .fill(BlueprintTheme.brandTeal.opacity(0.10))
                    .frame(width: 350, height: 350)
                    .blur(radius: 120)
                    .offset(x: 160, y: -220)
            }
        )
    }
}

// MARK: - Legacy Compatibility (keeping for existing code references)

extension View {
    func blueprintPrimaryOnDark() -> some View { self.foregroundStyle(Color.white.opacity(0.92)) }
    func blueprintSecondaryOnDark() -> some View { self.foregroundStyle(Color.white.opacity(0.75)) }
    func blueprintTertiaryOnDark() -> some View { self.foregroundStyle(Color.white.opacity(0.62)) }
    func blueprintGradientText() -> some View {
        self.foregroundStyle(BlueprintTheme.brandTeal)
    }

    /// Alias for blueprintAppBackground for screen-level backgrounds
    func blueprintScreenBackground() -> some View {
        self.blueprintAppBackground()
    }
}

struct BlueprintGlassCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

/// Alias for BlueprintGlassCard for convenience
typealias BlueprintCard = BlueprintGlassCard
