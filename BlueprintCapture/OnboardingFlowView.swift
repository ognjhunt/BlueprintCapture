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
        VStack(spacing: 32) {
            Spacer()

            // Hero
            VStack(spacing: 20) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(BlueprintTheme.brandTeal)

                Text("Earn money\nmapping spaces")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("Capture 3D scans of local businesses and get paid for each approved scan.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            // Features
            VStack(spacing: 16) {
                featureRow(icon: "clock", text: "Scans take 15-30 minutes")
                featureRow(icon: "dollarsign.circle", text: "Earn $20-50 per scan")
                featureRow(icon: "iphone", text: "Use your iPhone or smart glasses")
            }
            .padding(.horizontal, 32)

            Spacer()

            Button(action: onContinue) {
                Text("Get Started")
            }
            .buttonStyle(BlueprintPrimaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(BlueprintTheme.brandTeal)
                .frame(width: 24)

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()
        }
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

    @Environment(\.scenePhase) private var scenePhase
    private let notificationService = NotificationService()

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(BlueprintTheme.brandTeal)

                Text("Enable Permissions")
                    .font(.title2.weight(.bold))

                Text("We need access to capture scans and find nearby opportunities.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 32)

            VStack(spacing: 12) {
                permissionRow(title: "Camera", icon: "camera.fill", granted: cameraGranted)
                permissionRow(title: "Microphone", icon: "mic.fill", granted: microphoneGranted)
                permissionRow(title: "Location", icon: "location.fill", granted: locationGranted)
                permissionRow(title: "Notifications", icon: "bell.fill", granted: notificationsGranted)
            }
            .padding(.horizontal, 24)

            Spacer()

            Button(action: enableAll) {
                if isRequesting {
                    ProgressView().tint(.white)
                } else {
                    Text("Enable All")
                }
            }
            .buttonStyle(BlueprintPrimaryButtonStyle())
            .disabled(isRequesting)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .task { refreshNotificationStatus() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                refreshPermissionStatuses()
                refreshNotificationStatus()
            }
        }
        .alert("Permissions Required", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Continue Anyway") { onContinue() }
        } message: {
            Text("Camera and location are required for scanning. Enable them in Settings to continue.")
        }
    }

    private func permissionRow(title: String, icon: String, granted: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(granted ? BlueprintTheme.successGreen : .secondary)
                .frame(width: 24)

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? BlueprintTheme.successGreen : .secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
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
            await requestNotifications()
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
    }

    private func requestMicrophone() async {
        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        await MainActor.run { self.microphoneGranted = granted }
        UserDeviceService.setPermission("microphone", granted: granted)
    }

    private func requestLocation() async {
        let granted = await LocationPermissionRequester.requestWhenInUse()
        await MainActor.run { self.locationGranted = granted }
        UserDeviceService.setPermission("location", granted: granted)
        if granted {
            if let coord = await OneShotLocationFetcher.fetch() {
                let prefetcher = NearbyDiscoveryPrefetcher()
                prefetcher.runOnceIfPossible(userLocation: coord, radiusMeters: 1609, limit: 25)
            }
        }
    }

    private func requestNotifications() async {
        await notificationService.requestAuthorizationIfNeeded()
        await MainActor.run { refreshNotificationStatus() }
        UserDeviceService.setPermission("notifications", granted: notificationsGranted)
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationsGranted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            }
        }
    }
}

// MARK: - Step 3: Payouts connection (optional for first run)
private struct PayoutsPromptView: View {
    let onConnect: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(BlueprintTheme.brandTeal)

                Text("Get Paid")
                    .font(.title2.weight(.bold))

                Text("Connect your bank account to receive payouts for completed scans.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 16) {
                featureRow(icon: "calendar", text: "Weekly payouts every Wednesday")
                featureRow(icon: "bolt.fill", text: "Instant transfers available")
                featureRow(icon: "lock.shield", text: "Secure via Stripe")
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button(action: onConnect) {
                    Text("Connect Bank Account")
                }
                .buttonStyle(BlueprintPrimaryButtonStyle())

                Button(action: onSkip) {
                    Text("Skip for Now")
                }
                .buttonStyle(BlueprintSecondaryButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(BlueprintTheme.brandTeal)
                .frame(width: 24)

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

// MARK: - Step 4: Completion
private struct CompletionView: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(BlueprintTheme.successGreen)

                Text("You're All Set!")
                    .font(.title.weight(.bold))

                Text("Find opportunities near you and start earning.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button(action: onFinish) {
                Text("Start Earning")
            }
            .buttonStyle(BlueprintPrimaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
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


