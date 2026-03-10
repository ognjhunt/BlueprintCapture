import SwiftUI
import AVFoundation
import UserNotifications
import CoreLocation

struct OnboardingFlowView: View {
    enum Step: Int, CaseIterable { case welcome, permissions, complete }

    @AppStorage("com.blueprint.isOnboarded") private var isOnboarded: Bool = false

    @State private var step: Step = .welcome

    var body: some View {
        NavigationStack {
            ZStack {
                switch step {
                case .welcome:
                    WelcomeIntroView(
                        onContinue: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { step = .permissions }
                        }
                    )
                case .permissions:
                    PermissionsEnableView(
                        onContinue: {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { step = .complete }
                        }
                    )
                case .complete:
                    CompletionView(
                        onFinish: {
                            isOnboarded = true
                            UserDeviceService.updateLocalUser(fields: ["finishedOnboarding": true])
                            AppSessionService.shared.log("onboardingComplete")
                        }
                    )
                }
            }
            .toolbar { ToolbarTitleContent(step: step) }
            .blueprintOnboardingBackground()
        }
    }
}

private struct WelcomeIntroView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Qualification-first capture")
                    .font(.callout)
                    .blueprintSecondaryOnDark()
                Text("Collect site evidence for a real task zone")
                    .font(.system(size: 28, weight: .heavy))
                    .blueprintGradientText()
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    BlueprintPill("Phone-first", icon: "iphone")
                    BlueprintPill("Task-zone guided", icon: "viewfinder")
                }
                HStack(spacing: 8) {
                    BlueprintPill("Evidence QA ready", icon: "checklist")
                    BlueprintPill("ARKit optional", icon: "arkit")
                }
            }

            TabView {
                ValueCard(icon: "doc.text.viewfinder", title: "Start from a submission", subtitle: "Define the site, task, and task-zone boundaries before recording anything.")
                ValueCard(icon: "camera.viewfinder", title: "Capture with your phone", subtitle: "Record a guided evidence pass with video, motion logs, and optional ARKit enrichment.")
                ValueCard(icon: "square.stack.3d.down.right", title: "Keep downstream outputs usable", subtitle: "Package the evidence so later geometry, labels, and structure artifacts can attach cleanly.")
            }
            .tabViewStyle(.page)
            .frame(height: 280)

            Spacer(minLength: 16)

            Button(action: onContinue) { Text("Set up capture") }
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

    private let notificationService = NotificationService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enable evidence capture")
                        .font(.title2).fontWeight(.bold)
                        .blueprintGradientText()
                    Text("Camera and microphone power the default phone workflow. Location helps tie the submission to the correct site.")
                        .font(.callout)
                        .blueprintSecondaryOnDark()
                }

                BlueprintGlassCard {
                    PermissionsRow(title: "Camera", description: "Records the walkthrough evidence", granted: cameraGranted)
                    Divider()
                    PermissionsRow(title: "Microphone", description: "Captures audio context for review and transcription", granted: microphoneGranted)
                    Divider()
                    PermissionsRow(title: "Location", description: "Anchors the submission to the correct site", granted: locationGranted)
                }

                BlueprintGlassCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: notificationsGranted ? "checkmark.seal.fill" : "bell.badge.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(notificationsGranted ? BlueprintTheme.successGreen : BlueprintTheme.primary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notifications (recommended)").font(.headline).blueprintPrimaryOnDark()
                            Text("Get reminders when an evidence pass finishes uploading or needs a recap.")
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
                        Text(grantedAll ? "Continue" : "Enable and continue")
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
    }

    private var grantedAll: Bool { cameraGranted && microphoneGranted && locationGranted }

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
                onContinue()
            }
        }
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
    }

    private func requestNotifications() {
        Task {
            await notificationService.requestAuthorizationIfNeeded()
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

private struct CompletionView: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(BlueprintTheme.successGreen)
                Text("You’re ready to qualify sites")
                    .font(.title2).fontWeight(.bold)
                    .blueprintGradientText()
                Text("Start from a manual submission, review the task zone, and record an evidence pass with your phone.")
                    .font(.subheadline).blueprintSecondaryOnDark()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 32)

            Spacer()

            Button(action: onFinish) { Text("Open capture workflow") }
                .buttonStyle(BlueprintPrimaryButtonStyle())
                .padding(.horizontal)
        }
        .padding()
    }
}

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
        case .complete: return "All set"
        }
    }
}
