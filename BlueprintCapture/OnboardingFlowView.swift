import SwiftUI
import AVFoundation
import CoreMotion
import UserNotifications

/// First-run onboarding flow inspired by modern gig apps (Uber, DoorDash):
/// 1) Value prop intro → 2) Enable capture permissions → 3) Optional payouts connection → 4) Done
struct OnboardingFlowView: View {
    enum Step: Int, CaseIterable { case welcome, permissions, payouts, complete }

    @AppStorage("com.blueprint.isOnboarded") private var isOnboarded: Bool = false

    @State private var step: Step = .welcome
    @State private var showingBankSetup = false

    var body: some View {
        NavigationStack {
            ZStack {
                switch step {
                case .welcome:
                    WelcomeIntroView(onContinue: { withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { step = .permissions } })
                case .permissions:
                    PermissionsEnableView(onContinue: { withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { step = .payouts } })
                case .payouts:
                    PayoutsPromptView(onConnect: { showingBankSetup = true }, onSkip: { withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { step = .complete } })
                case .complete:
                    CompletionView(onFinish: { isOnboarded = true })
                }
            }
            .toolbar { ToolbarTitleContent(step: step) }
            .sheet(isPresented: $showingBankSetup) {
                // Lightweight handoff into existing bank connection flow
                StripeBillingSetupView(viewModel: SettingsViewModel())
            }
            .blueprintOnboardingBackground()
        }
    }
}

// MARK: - Step 1: Welcome / Value Props
private struct WelcomeIntroView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                (Text("What you can do with ") + Text("Blueprint").bold())
                    .font(.title3)
                    .blueprintSecondaryOnDark()
                Text("Space scans, agent flows, and hardware provisioning.")
                    .font(.system(size: 32, weight: .heavy))
                    .blueprintGradientText()
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)

            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    BlueprintPill("Venue scan < 60 min", icon: "timer")
                    BlueprintPill("All smart glasses", icon: "eyeglasses")
                }
                HStack(spacing: 8) {
                    BlueprintPill("Playbooks included", icon: "book")
                    BlueprintPill("Analytics ready", icon: "chart.bar")
                }
            }

            TabView {
                ValueCard(icon: "mappin.and.ellipse", title: "Find nearby jobs", subtitle: "Pick locations near you and start a walkthrough.")
                ValueCard(icon: "camera.viewfinder", title: "Simple capture flow", subtitle: "Our AI guides you—no special hardware required.")
                ValueCard(icon: "dollarsign.circle.fill", title: "Get paid fast", subtitle: "Payouts through Stripe. Connect your bank in minutes.")
            }
            .tabViewStyle(.page)
            .frame(height: 280)

            Spacer(minLength: 16)

            Button(action: onContinue) { Text("Launch your solution") }
                .buttonStyle(BlueprintPrimaryButtonStyle())
                .padding(.horizontal)
        }
        .padding()
    }
}

private struct ValueCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(BlueprintTheme.primary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(BlueprintTheme.surface)
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 6)
        )
        .padding(.horizontal)
    }
}

// MARK: - Step 2: Permissions
private struct PermissionsEnableView: View {
    let onContinue: () -> Void

    @State private var cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var microphoneGranted = AVAudioSession.sharedInstance().recordPermission == .granted
    @State private var motionGranted: Bool = {
        if CMMotionActivityManager.isActivityAvailable() {
            return CMMotionActivityManager.authorizationStatus() == .authorized
        } else { return true }
    }()
    @State private var notificationsGranted = false
    @State private var isRequesting = false

    private let notificationService = NotificationService()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Enable capture sensors")
                    .font(.title2).fontWeight(.bold)
                    .blueprintGradientText()
                Text("We use your camera, microphone and motion sensors to build metrically-accurate walkthroughs.")
                    .font(.callout)
                    .blueprintSecondaryOnDark()
            }

            BlueprintGlassCard {
                PermissionsRow(title: "Camera", description: "Records the visual walkthrough", granted: cameraGranted)
                Divider()
                PermissionsRow(title: "Microphone", description: "Captures spatial audio for AI transcription", granted: microphoneGranted)
                Divider()
                PermissionsRow(title: "Motion & Fitness", description: "Adds device pose for metric scale", granted: motionGranted)
            }

            BlueprintGlassCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: notificationsGranted ? "checkmark.seal.fill" : "bell.badge.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(notificationsGranted ? BlueprintTheme.successGreen : BlueprintTheme.primary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notifications (optional)").font(.headline).blueprintPrimaryOnDark()
                        Text("Get reminders when you’re near a job.")
                            .font(.subheadline).blueprintSecondaryOnDark()
                        Button(action: requestNotifications) { Text(notificationsGranted ? "Enabled" : "Enable notifications") }
                            .buttonStyle(BlueprintSecondaryButtonStyle())
                            .disabled(notificationsGranted)
                    }
                    Spacer()
                }
            }

            Spacer()

            Button(action: enableAll) {
                HStack {
                    if isRequesting { ProgressView().tint(.white) }
                    Text(grantedAll ? "Continue" : "Enable & continue")
                }
            }
            .buttonStyle(BlueprintPrimaryButtonStyle())
            .disabled(isRequesting)
        }
        .padding()
        .task { refreshNotificationStatus() }
    }

    private var grantedAll: Bool { cameraGranted && microphoneGranted && motionGranted }

    private func enableAll() {
        if grantedAll {
            onContinue()
            return
        }
        isRequesting = true
        Task {
            await requestCamera()
            await requestMicrophone()
            await requestMotion()
            await MainActor.run {
                isRequesting = false
                onContinue()
            }
        }
    }

    private func requestCamera() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run { self.cameraGranted = granted }
    }

    private func requestMicrophone() async {
        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        await MainActor.run { self.microphoneGranted = granted }
    }

    private func requestMotion() async {
        guard CMMotionActivityManager.isActivityAvailable() else {
            await MainActor.run { self.motionGranted = true }
            return
        }
        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized:
            await MainActor.run { self.motionGranted = true }
        case .denied, .restricted:
            await MainActor.run { self.motionGranted = false }
        case .notDetermined:
            let manager = CMMotionActivityManager()
            let start = Date().addingTimeInterval(-60)
            try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                manager.queryActivityStarting(from: start, to: Date(), to: OperationQueue.main) { _, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            await MainActor.run { self.motionGranted = CMMotionActivityManager.authorizationStatus() == .authorized }
        @unknown default:
            await MainActor.run { self.motionGranted = false }
        }
    }

    private func requestNotifications() {
        Task { await notificationService.requestAuthorizationIfNeeded(); refreshNotificationStatus() }
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationsGranted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            }
        }
    }
}

private struct PermissionsRow: View {
    let title: String
    let description: String
    let granted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(granted ? BlueprintTheme.successGreen : BlueprintTheme.warningOrange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(description).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Step 3: Payouts connection (optional for first run)
private struct PayoutsPromptView: View {
    let onConnect: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Get paid with Stripe")
                    .font(.title2).fontWeight(.bold)
                    .blueprintGradientText()
                Text("Connect a bank account now or later. You can start scanning immediately.")
                    .font(.callout).blueprintSecondaryOnDark()
            }

            BlueprintGlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "building.columns.fill").foregroundStyle(BlueprintTheme.accentAqua)
                        Text("Secure bank connection via Plaid")
                            .font(.subheadline)
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "calendar").foregroundStyle(BlueprintTheme.primary)
                        Text("Standard payouts in ~2 business days")
                            .font(.subheadline)
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "bolt.fill").foregroundStyle(BlueprintTheme.warningOrange)
                        Text("Instant cash-out available once eligible")
                            .font(.subheadline)
                    }
                }
            }

            Spacer()

            Button(action: onConnect) { HStack { Image(systemName: "link"); Text("Connect bank account") } }
                .buttonStyle(BlueprintPrimaryButtonStyle())
            Button(action: onSkip) { Text("Do this later") }
                .buttonStyle(BlueprintSecondaryButtonStyle())
        }
        .padding()
    }
}

// MARK: - Step 4: Completion
private struct CompletionView: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(BlueprintTheme.successGreen)
                Text("You’re ready to scan")
                    .font(.title2).fontWeight(.bold)
                    .blueprintGradientText()
                Text("You can find locations near you or start a new walkthrough now.")
                    .font(.subheadline).blueprintSecondaryOnDark()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 32)

            Spacer()

            Button(action: onFinish) { Text("Start scanning") }
                .buttonStyle(BlueprintPrimaryButtonStyle())
                .padding(.horizontal)
        }
        .padding()
    }
}

// MARK: - Toolbar title with subtle styling
private struct ToolbarTitleContent: ToolbarContent {
    let step: OnboardingFlowView.Step
    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
    private var title: String {
        switch step {
        case .welcome: return "Welcome"
        case .permissions: return "Permissions"
        case .payouts: return "Payouts"
        case .complete: return "All set"
        }
    }
}


