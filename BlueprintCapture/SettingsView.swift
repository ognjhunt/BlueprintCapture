import SwiftUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var notificationPreferences: NotificationPreferencesStore
    @StateObject private var alertsManager = NearbyAlertsManager()
    @State private var showingStripeOnboarding = false
    @State private var showingManagePayouts = false
    @State private var showingEditProfile = false
    @State private var showingAuth = false
    @State private var showingGlassesCapture = false
    @State private var showNearbyAlertInfo = false
    @State private var showDeleteAccountConfirmation = false

    // Toggle states
    @AppStorage("upload_wifi_only") private var wifiOnlyUploads = false
    @AppStorage("upload_auto_clear") private var autoClearCompleted = true
    @AppStorage("capture_haptics") private var captureHaptics = true

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    pageHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 28)

                    // Profile section
                    sectionLabel("Profile")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                    profileCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    // Payouts section
                    sectionLabel("Payouts")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                    payoutsCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    // Capture settings
                    sectionLabel("Capture")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                    captureCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    // Notifications
                    sectionLabel("Notifications")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                    notificationsCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    // Useful Links
                    sectionLabel("Useful Links")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                    usefulLinksCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    // Legal
                    sectionLabel("Legal")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                    legalCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    // Technical
                    sectionLabel("Technical Details")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                    technicalCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 48)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showingManagePayouts) { ManagePayoutsView() }
        .sheet(isPresented: $showingStripeOnboarding) { StripeOnboardingView() }
        .sheet(isPresented: $showingEditProfile) { EditProfileView(viewModel: viewModel) }
        .sheet(isPresented: $showingAuth) { AuthView() }
        .sheet(isPresented: $showingGlassesCapture) { GlassesCaptureView() }
        .task {
            await viewModel.loadUserData()
            await notificationPreferences.refreshFromBackendIfPossible()
        }
        .alert("Settings Error", isPresented: $viewModel.showError, presenting: viewModel.error) { _ in
            Button("OK", role: .cancel) { }
        } message: { error in
            Text(error.errorDescription ?? "Something went wrong.")
        }
        .alert("Delete Account?", isPresented: $showDeleteAccountConfirmation) {
            Button("Delete Account", role: .destructive) {
                Task {
                    _ = await viewModel.deleteAccount()
                }
            }
            if AppConfig.accountDeletionURL() != nil {
                Button("Deletion Help") {
                    openExternalLink(AppConfig.accountDeletionURL())
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes your Blueprint account and signs this device out. If deletion fails, use the support links to request manual removal.")
        }
        .alert("Nearby job alerts use Always Location", isPresented: $showNearbyAlertInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("To alert you when you approach an approved capture opportunity, iOS needs Always Location permission for nearby job alerts.")
        }
    }

    // MARK: - Header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Settings")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
            Text("Manage your account and preferences")
                .font(.subheadline)
                .foregroundStyle(Color(white: 0.45))
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        kledCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(BlueprintTheme.brandTeal.opacity(0.18))
                        .frame(width: 52, height: 52)
                    Image(systemName: "person.fill")
                        .font(.title3)
                        .foregroundStyle(BlueprintTheme.brandTeal)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.profile.fullName.isEmpty ? "Capturer" : viewModel.profile.fullName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(viewModel.profile.email.isEmpty ? "Not signed in" : viewModel.profile.email)
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.45))
                }

                Spacer()

                if viewModel.isAuthenticated {
                    Button {
                        viewModel.startEditingProfile()
                        showingEditProfile = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(white: 0.5))
                            .frame(width: 32, height: 32)
                            .background(Color(white: 0.15), in: Circle())
                    }
                } else {
                    Button("Sign In") { showingAuth = true }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.brandTeal)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(BlueprintTheme.brandTeal.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    // MARK: - Payouts Card

    private var payoutsCard: some View {
        kledCard {
            VStack(spacing: 0) {
                settingsNavRow(
                    icon: "creditcard.fill",
                    iconBg: BlueprintTheme.successGreen,
                    title: "Manage Payouts",
                    subtitle: "Venmo, PayPal, Crypto, Stripe"
                ) { showingManagePayouts = true }

                kledRowDivider

                settingsNavRow(
                    icon: "building.columns.fill",
                    iconBg: BlueprintTheme.primary,
                    title: "Connect Bank Account",
                    subtitle: "Stripe payouts for approved scans"
                ) { showingStripeOnboarding = true }

                kledRowDivider

                settingsNavRow(
                    icon: "eyeglasses",
                    iconBg: BlueprintTheme.brandTeal,
                    title: "Capture Glasses",
                    subtitle: "Connect Meta smart glasses"
                ) { showingGlassesCapture = true }
            }
        }
    }

    // MARK: - Capture Card

    private var captureCard: some View {
        kledCard {
            VStack(spacing: 0) {
                settingsToggleRow(
                    icon: "wifi",
                    iconBg: Color(red: 0.2, green: 0.6, blue: 1.0),
                    title: "Wi-Fi Only Uploads",
                    subtitle: "Prevent uploads over cellular data",
                    value: $wifiOnlyUploads
                )

                kledRowDivider

                settingsToggleRow(
                    icon: "checkmark.circle.fill",
                    iconBg: BlueprintTheme.successGreen,
                    title: "Auto-Clear Completed",
                    subtitle: "Remove completed items from queue",
                    value: $autoClearCompleted
                )

                kledRowDivider

                settingsToggleRow(
                    icon: "waveform",
                    iconBg: Color.purple,
                    title: "Capture Haptics",
                    subtitle: "Vibration feedback during capture",
                    value: $captureHaptics
                )
            }
        }
    }

    // MARK: - Notifications Card

    private var notificationsCard: some View {
        kledCard {
            VStack(spacing: 0) {
                settingsToggleRow(
                    icon: "location.fill",
                    iconBg: BlueprintTheme.brandTeal,
                    title: NotificationPreferenceKey.nearbyJobs.title,
                    subtitle: NotificationPreferenceKey.nearbyJobs.subtitle,
                    value: binding(for: .nearbyJobs)
                )

                kledRowDivider

                settingsToggleRow(
                    icon: "timer",
                    iconBg: Color.orange,
                    title: NotificationPreferenceKey.reservations.title,
                    subtitle: NotificationPreferenceKey.reservations.subtitle,
                    value: binding(for: .reservations)
                )

                kledRowDivider

                settingsToggleRow(
                    icon: "checkmark.seal.fill",
                    iconBg: BlueprintTheme.successGreen,
                    title: NotificationPreferenceKey.captureStatus.title,
                    subtitle: NotificationPreferenceKey.captureStatus.subtitle,
                    value: binding(for: .captureStatus)
                )

                kledRowDivider

                settingsToggleRow(
                    icon: "banknote.fill",
                    iconBg: Color(red: 0.2, green: 0.6, blue: 1.0),
                    title: NotificationPreferenceKey.payouts.title,
                    subtitle: NotificationPreferenceKey.payouts.subtitle,
                    value: binding(for: .payouts)
                )

                kledRowDivider

                settingsToggleRow(
                    icon: "exclamationmark.circle.fill",
                    iconBg: Color(red: 0.85, green: 0.45, blue: 0.2),
                    title: NotificationPreferenceKey.account.title,
                    subtitle: NotificationPreferenceKey.account.subtitle,
                    value: binding(for: .account)
                )
            }
        }
    }

    // MARK: - Useful Links Card

    private var usefulLinksCard: some View {
        kledCard {
            VStack(spacing: 0) {
                settingsLinkRow(icon: "globe", iconBg: Color(white: 0.25), title: "Main Website") {
                    openExternalLink(AppConfig.mainWebsiteURL())
                }
                kledRowDivider
                settingsLinkRow(icon: "questionmark.circle.fill", iconBg: Color(white: 0.25), title: "Help Center") {
                    openExternalLink(AppConfig.helpCenterURL())
                }
                kledRowDivider
                settingsLinkRow(icon: "ant.fill", iconBg: Color.red.opacity(0.8), title: "Report a Bug") {
                    openExternalLink(AppConfig.bugReportURL())
                }
            }
        }
    }

    // MARK: - Legal Card

    private var legalCard: some View {
        kledCard {
            VStack(spacing: 0) {
                settingsLinkRow(icon: "doc.text.fill", iconBg: Color(white: 0.25), title: "Terms of Service") {
                    openExternalLink(AppConfig.termsOfServiceURL())
                }
                kledRowDivider
                settingsLinkRow(icon: "hand.raised.fill", iconBg: Color(white: 0.25), title: "Privacy Policy") {
                    openExternalLink(AppConfig.privacyPolicyURL())
                }
                kledRowDivider
                settingsLinkRow(icon: "camera.fill", iconBg: Color(white: 0.25), title: "Capture Policy") {
                    openExternalLink(AppConfig.capturePolicyURL())
                }
            }
        }
    }

    // MARK: - Technical Card

    private var technicalCard: some View {
        kledCard {
            VStack(spacing: 0) {
                infoRow(label: "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                kledRowDivider
                infoRow(label: "Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                kledRowDivider

                if viewModel.isAuthenticated {
                    kledRowDivider
                    settingsDestructiveRow(
                        icon: "trash.fill",
                        title: "Delete Account",
                        detail: "Remove your account or request manual deletion"
                    ) {
                        showDeleteAccountConfirmation = true
                    }

                    kledRowDivider
                    Button {
                        Task { await viewModel.signOut() }
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.red)
                                .frame(width: 36, height: 36)
                                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            Text("Sign Out")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.red)

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Reusable Row Components

    private func settingsNavRow(icon: String, iconBg: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(iconBg.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.4))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(white: 0.25))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func settingsToggleRow(icon: String, iconBg: Color, title: String, subtitle: String, value: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(iconBg.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.4))
            }

            Spacer()

            Toggle("", isOn: value)
                .labelsHidden()
                .tint(BlueprintTheme.brandTeal)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func binding(for key: NotificationPreferenceKey) -> Binding<Bool> {
        Binding(
            get: { notificationPreferences.isEnabled(key) },
            set: { newValue in
                notificationPreferences.set(key, enabled: newValue)
                Task {
                    if newValue {
                        await PushNotificationManager.shared.requestAuthorizationIfNeeded()
                    }
                }
                if key == .nearbyJobs && newValue && !alertsManager.isAlwaysAuthorized {
                    showNearbyAlertInfo = true
                    alertsManager.requestAlwaysAuthorization()
                }
            }
        )
    }

    private func settingsLinkRow(icon: String, iconBg: Color, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(iconBg.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(white: 0.25))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func settingsDestructiveRow(icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(width: 36, height: 36)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.4))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(white: 0.25))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color(white: 0.6))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

    private func kledCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(white: 0.12), lineWidth: 1)
            )
    }

    private var kledRowDivider: some View {
        Rectangle()
            .fill(Color(white: 0.12))
            .frame(height: 1)
            .padding(.leading, 66)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(Color(white: 0.35))
            .tracking(1.0)
    }

    private func openExternalLink(_ url: URL?) {
        guard let url else { return }
        openURL(url)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .preferredColorScheme(.dark)
}
