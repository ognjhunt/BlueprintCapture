import SwiftUI

// Visual design system for Blueprint Capture
// Centralizes brand colors, gradients, and reusable styles so all screens feel cohesive.
enum BlueprintTheme {
    // Primary brand colors – trustworthy blue palette
    static let primary        = Color(red: 0.12, green: 0.44, blue: 0.98)    // Blueprint Blue
    static let primaryDeep    = Color(red: 0.04, green: 0.20, blue: 0.55)    // Deep Navy
    static let brandTeal      = Color(red: 0.32, green: 0.93, blue: 0.84)    // Website accent teal
    static let payoutTeal     = Color(red: 0.16, green: 0.72, blue: 0.64)    // Darker teal for payout values
    static let accentAqua     = Color(red: 0.12, green: 0.76, blue: 0.95)
    static let successGreen   = Color(red: 0.18, green: 0.68, blue: 0.43)
    static let warningOrange  = Color(red: 0.98, green: 0.58, blue: 0.20)
    static let errorRed       = Color(red: 0.92, green: 0.20, blue: 0.20)

    // Neutrals
    static let surface        = Color(.secondarySystemBackground)
    static let surfaceElevated = Color(.tertiarySystemBackground)
    static let bgDark         = Color(red: 0.06, green: 0.08, blue: 0.12)
    static let bgDarker       = Color(red: 0.03, green: 0.05, blue: 0.09)

    // Background gradient for hero/top sections
    static let heroGradient = LinearGradient(
        colors: [primaryDeep.opacity(0.95), primary.opacity(0.85)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Onboarding gradient, tuned to match website hero
    static let onboardingGradient = LinearGradient(
        colors: [bgDarker, Color(red: 0.05, green: 0.10, blue: 0.18)],
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

    // Richer background for onboarding: dark hero + brand glows
    func blueprintOnboardingBackground() -> some View {
        self
            .background(
                ZStack {
                    BlueprintTheme.onboardingGradient
                        .ignoresSafeArea()

                    // Brand glows
                    Circle()
                        .fill(BlueprintTheme.primary.opacity(0.18))
                        .frame(width: 420, height: 420)
                        .blur(radius: 120)
                        .offset(x: -160, y: -260)

                    Circle()
                        .fill(BlueprintTheme.brandTeal.opacity(0.16))
                        .frame(width: 380, height: 380)
                        .blur(radius: 120)
                        .offset(x: 160, y: -220)

                    Circle()
                        .fill(BlueprintTheme.accentAqua.opacity(0.12))
                        .frame(width: 500, height: 500)
                        .blur(radius: 140)
                        .offset(x: 0, y: 420)
                }
            )
    }

    // Gradient foreground for headings matching website brand
    func blueprintGradientText() -> some View {
        self
            .foregroundStyle(
                LinearGradient(colors: [BlueprintTheme.brandTeal, BlueprintTheme.accentAqua, BlueprintTheme.primary], startPoint: .leading, endPoint: .trailing)
            )
    }

    // High-contrast text helpers for dark backgrounds
    func blueprintPrimaryOnDark() -> some View { self.foregroundStyle(Color.white.opacity(0.92)) }
    func blueprintSecondaryOnDark() -> some View { self.foregroundStyle(Color.white.opacity(0.75)) }
    func blueprintTertiaryOnDark() -> some View { self.foregroundStyle(Color.white.opacity(0.62)) }

    // Subtle app-wide background for non-onboarding screens
    func blueprintAppBackground() -> some View {
        self.background(
            ZStack {
                LinearGradient(colors: [BlueprintTheme.bgDarker, BlueprintTheme.bgDark], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                Circle().fill(BlueprintTheme.primary.opacity(0.10)).frame(width: 380, height: 380).blur(radius: 120).offset(x: -160, y: -280)
                Circle().fill(BlueprintTheme.brandTeal.opacity(0.10)).frame(width: 320, height: 320).blur(radius: 120).offset(x: 200, y: 360)
            }
        )
    }
}

// MARK: - Glass components (used by onboarding)
struct BlueprintGlassCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(LinearGradient(colors: [Color.white.opacity(0.25), Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                        .blendMode(.overlay)
                )
        )
    }
}

struct BlueprintPill: View {
    let text: String
    let icon: String?

    init(_ text: String, icon: String? = nil) { self.text = text; self.icon = icon }

    var body: some View {
        HStack(spacing: 8) {
            if let icon { Image(systemName: icon) }
            Text(text)
                .font(.footnote.weight(.semibold))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 999, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .foregroundStyle(Color.white.opacity(0.9))
    }
}


