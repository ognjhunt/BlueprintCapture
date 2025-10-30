import SwiftUI
import AVFoundation
import UserNotifications
import CoreLocation
import FirebaseAuth
import UIKit

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
                    CompletionView(onFinish: {
                        isOnboarded = true
                        // Mark onboarding finished on local user
                        UserDeviceService.updateLocalUser(fields: ["finishedOnboarding": true])
                        AppSessionService.shared.log("onboardingComplete")
                    })
                }
            }
            .toolbar { ToolbarTitleContent(step: step) }
            .sheet(isPresented: $showingBankSetup) {
                StripeOnboardingView()
            }
            .blueprintOnboardingBackground()
        }
    }
}

// MARK: - Step 1: Welcome / Value Props
private struct WelcomeIntroView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Start mapping with Blueprint")
                    .font(.callout)
                    .blueprintSecondaryOnDark()
                Text("Earn $50/hr mapping spaces")
                    .font(.system(size: 28, weight: .heavy))
                    .blueprintGradientText()
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    BlueprintPill("Scans < 30 min", icon: "timer")
                    BlueprintPill("iPhone or glasses", icon: "camera")
                }
                HStack(spacing: 8) {
                    BlueprintPill("Playbooks included", icon: "book")
                    BlueprintPill("Earn in 5 mins", icon: "bolt.fill")
                }
            }

            TabView {
                ValueCard(icon: "mappin.and.ellipse", title: "Discover nearby spaces", subtitle: "Find high-value indoor locations near you ready to capture for detailed 3D scans.")
                ValueCard(icon: "camera.viewfinder", title: "Capture with your phone", subtitle: "Record a guided walkthrough using your iPhone or AI glasses—we handle the rest.")
                ValueCard(icon: "dollarsign.circle.fill", title: "Earn while you map", subtitle: "Get paid for each scan after processing. Fast payouts via Stripe.")
            }
            .tabViewStyle(.page)
            .frame(height: 280)

            Spacer(minLength: 16)

            Button(action: onContinue) { Text("Get started — earn in 5 mins") }
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
    @State private var locationGranted: Bool = {
        let status = CLLocationManager().authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }()
    @State private var notificationsGranted = false
    @State private var isRequesting = false
    @State private var showingPermissionAlert = false

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    private let notificationService = NotificationService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                    PermissionsRow(title: "Location", description: "Pins your captures to the correct address", granted: locationGranted)
                }

                BlueprintGlassCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: notificationsGranted ? "checkmark.seal.fill" : "bell.badge.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(notificationsGranted ? BlueprintTheme.successGreen : BlueprintTheme.primary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notifications (recommended)").font(.headline).blueprintPrimaryOnDark()
                            Text("Get reminders when you're near a job.")
                                .font(.subheadline).blueprintSecondaryOnDark()
                            Button(action: requestNotifications) { Text(notificationsGranted ? "Enabled" : "Enable notifications") }
                                .buttonStyle(BlueprintSecondaryButtonStyle())
                                .disabled(notificationsGranted)
                        }
                        Spacer()
                    }
                }

                Button(action: enableAll) {
                    HStack {
                        if isRequesting { ProgressView().tint(.white) }
                        Text(grantedAll ? "Continue" : "Enable & continue")
                    }
                }
                .buttonStyle(BlueprintPrimaryButtonStyle())
                .disabled(isRequesting)
                .padding(.bottom, 8)
            }
            .padding(.horizontal)
            .padding(.top, -15)
        }
        .task { refreshNotificationStatus() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                refreshPermissionStatuses()
                refreshNotificationStatus()
            }
        }
        .alert("Permissions required", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                guard
                    let settingsURL = URL(string: UIApplication.openSettingsURLString),
                    UIApplication.shared.canOpenURL(settingsURL)
                else { return }

                UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Blueprint needs access to your camera and location to continue. Please enable these permissions in Settings to proceed.")
        }
    }

    private var grantedAll: Bool { cameraGranted && microphoneGranted && locationGranted }
    private var requiredPermissionsGranted: Bool { cameraGranted && locationGranted }

    private func enableAll() {
        if grantedAll {
            onContinue()
            return
        }
        isRequesting = true
        Task {
            await requestCamera()
            await requestMicrophone()
            await requestLocation()
            await MainActor.run {
                isRequesting = false
                if requiredPermissionsGranted {
                    onContinue()
                } else {
                    showingPermissionAlert = true
                }
            }
        }
    }

    private func refreshPermissionStatuses() {
        cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        microphoneGranted = AVAudioSession.sharedInstance().recordPermission == .granted
        let status = CLLocationManager().authorizationStatus
        locationGranted = status == .authorizedWhenInUse || status == .authorizedAlways
    }

    private func requestCamera() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run { self.cameraGranted = granted }
        UserDeviceService.setPermission("camera", granted: granted)
        AppSessionService.shared.log("permission.camera", metadata: ["granted": granted])
    }

    private func requestMicrophone() async {
        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        await MainActor.run { self.microphoneGranted = granted }
        UserDeviceService.setPermission("microphone", granted: granted)
        AppSessionService.shared.log("permission.microphone", metadata: ["granted": granted])
    }

    private func requestLocation() async {
        let granted = await LocationPermissionRequester.requestWhenInUse()
        await MainActor.run { self.locationGranted = granted }
        UserDeviceService.setPermission("location", granted: granted)
        AppSessionService.shared.log("permission.location", metadata: ["granted": granted])
        // Kick off discovery prefetch as soon as we have permission and a coordinate
        if granted {
            if let coord = await OneShotLocationFetcher.fetch() {
                let prefetcher = NearbyDiscoveryPrefetcher()
                prefetcher.runOnceIfPossible(userLocation: coord, radiusMeters: 1609, limit: 25)
                AppSessionService.shared.log("prefetch.nearby", metadata: ["lat": coord.latitude, "lng": coord.longitude])
            }
        }
    }

    private func requestNotifications() {
        Task {
            await notificationService.requestAuthorizationIfNeeded();
            refreshNotificationStatus()
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let granted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
                UserDeviceService.setPermission("notifications", granted: granted)
                AppSessionService.shared.log("permission.notifications", metadata: ["granted": granted])
            }
        }
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
                Text(title)
                    .font(.headline)
                    .blueprintPrimaryOnDark()
                Text(description)
                    .font(.subheadline)
                    .blueprintSecondaryOnDark()
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(granted ? 0.10 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(granted ? 0.14 : 0.06), lineWidth: 1)
        )
    }
}

// MARK: - Step 3: Payouts connection (optional for first run)
private struct PayoutsPromptView: View {
    let onConnect: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How payouts work")
                    .font(.title2).fontWeight(.bold)
                    .blueprintGradientText()
                Text("Connect a bank account now or later. You can start scanning immediately.")
                    .font(.callout).blueprintSecondaryOnDark()
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "calendar").foregroundStyle(BlueprintTheme.primary)
                    Text("Default: Weekly payouts for Mon–Sun, deposited Wed–Thu")
                        .font(.subheadline)
                        .blueprintPrimaryOnDark()
                }
                HStack(spacing: 12) {
                    Image(systemName: "creditcard.fill").foregroundStyle(BlueprintTheme.accentAqua)
                    Text("After each capture: Auto-deposit to Blueprint Card (no fee)")
                        .font(.subheadline)
                        .blueprintPrimaryOnDark()
                }
                HStack(spacing: 12) {
                    Image(systemName: "bolt.fill").foregroundStyle(BlueprintTheme.warningOrange)
                    Text("Instant Pay: Same-day cash out to your debit (fee applies)")
                        .font(.subheadline)
                        .blueprintPrimaryOnDark()
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )

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


