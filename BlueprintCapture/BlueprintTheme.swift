import SwiftUI

/// Shared visual system for Blueprint Capture.
/// The active direction is a monochrome, documentary, editorial mobile UI.
enum BlueprintTheme {
    // MARK: - Core Palette
    static let primary = Color(red: 0.95, green: 0.95, blue: 0.94)
    static let primaryDeep = Color(red: 0.74, green: 0.74, blue: 0.72)
    static let brandTeal = Color(red: 0.92, green: 0.92, blue: 0.90)
    static let accentAqua = Color(red: 0.80, green: 0.80, blue: 0.77)

    // MARK: - Semantic Colors
    static let successGreen = Color(red: 0.94, green: 0.94, blue: 0.92)
    static let warningOrange = Color(red: 0.77, green: 0.77, blue: 0.74)
    static let errorRed = Color(red: 0.86, green: 0.86, blue: 0.84)

    // MARK: - Background Colors
    static let bgDark = Color(red: 0.06, green: 0.06, blue: 0.07)
    static let bgDarker = Color(red: 0.02, green: 0.02, blue: 0.03)
    static let surface = Color(red: 0.10, green: 0.10, blue: 0.11)
    static let surfaceElevated = Color(red: 0.14, green: 0.14, blue: 0.15)

    // MARK: - Monochrome UI Tokens
    static let kledBackground = Color.black
    static let kledCard = Color(red: 0.09, green: 0.09, blue: 0.10)
    static let kledCardBorder = Color(red: 0.18, green: 0.18, blue: 0.19)
    static let kledSecondary = Color(red: 0.58, green: 0.58, blue: 0.60)
    static let hairline = Color.white.opacity(0.10)
    static let textPrimary = Color.white.opacity(0.96)
    static let textSecondary = Color.white.opacity(0.66)
    static let textTertiary = Color.white.opacity(0.42)
    static let panel = Color(red: 0.08, green: 0.08, blue: 0.09)
    static let panelStrong = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let panelMuted = Color(red: 0.06, green: 0.06, blue: 0.07)
    static let overlay = Color.black.opacity(0.64)
    static let shadow = Color.black.opacity(0.36)

    // MARK: - Typography
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: - Gradients
    static let onboardingGradient = LinearGradient(
        colors: [bgDarker, bgDark, Color(red: 0.10, green: 0.10, blue: 0.11)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGradient = LinearGradient(
        colors: [Color.white.opacity(0.10), Color.clear, Color.white.opacity(0.04)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let reservedGradient = LinearGradient(
        colors: [Color.white.opacity(0.10), Color.white.opacity(0.02)],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Button Styles

struct BlueprintPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BlueprintTheme.body(16, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.vertical, 17)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(BlueprintTheme.primary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: BlueprintTheme.shadow, radius: 16, x: 0, y: 8)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct BlueprintSuccessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BlueprintTheme.body(16, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.vertical, 17)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(BlueprintTheme.successGreen)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.92 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct BlueprintSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BlueprintTheme.body(16, weight: .semibold))
            .foregroundStyle(BlueprintTheme.textPrimary)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(BlueprintTheme.panelStrong)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BlueprintTheme.hairline, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - View Extensions

extension View {
    func blueprintAppBackground() -> some View {
        self.background(
            ZStack {
                LinearGradient(
                    colors: [BlueprintTheme.bgDarker, BlueprintTheme.bgDark, Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 420, height: 420)
                    .blur(radius: 160)
                    .offset(x: -180, y: -340)

                Circle()
                    .fill(Color.white.opacity(0.03))
                    .frame(width: 360, height: 360)
                    .blur(radius: 150)
                    .offset(x: 210, y: 420)
            }
        )
    }

    func blueprintOnboardingBackground() -> some View {
        self.background(
            ZStack {
                BlueprintTheme.onboardingGradient
                    .ignoresSafeArea()

                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 420, height: 420)
                    .blur(radius: 160)
                    .offset(x: -160, y: -280)

                Circle()
                    .fill(Color.white.opacity(0.03))
                    .frame(width: 320, height: 320)
                    .blur(radius: 140)
                    .offset(x: 160, y: -220)
            }
        )
    }

    func blueprintPanelBackground(
        radius: CGFloat = 20,
        fill: Color = BlueprintTheme.panel,
        stroke: Color = BlueprintTheme.hairline
    ) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(stroke, lineWidth: 1)
        )
    }

    func blueprintEditorialCard(radius: CGFloat = 20, fill: Color = BlueprintTheme.panel) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(BlueprintTheme.hairline, lineWidth: 1)
            )
            .shadow(color: BlueprintTheme.shadow, radius: 18, x: 0, y: 10)
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
        .blueprintEditorialCard(radius: 18, fill: BlueprintTheme.panel)
    }
}

/// Alias for BlueprintGlassCard for convenience
typealias BlueprintCard = BlueprintGlassCard
