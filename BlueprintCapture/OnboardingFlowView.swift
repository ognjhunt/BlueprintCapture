import SwiftUI
import AVFoundation
import UserNotifications
import CoreLocation
import UIKit

/// iPhone-first onboarding:
/// 1) Welcome -> 2) Permissions -> 3) Device Capability -> 4) Tutorial -> 5) Connect Glasses (optional) -> Done
struct OnboardingFlowView: View {
    enum Step: Int, CaseIterable { case welcome, permissions, deviceCapability, tutorial, connectGlasses, complete }

    @AppStorage("com.blueprint.isOnboarded") private var isOnboarded: Bool = false

    @ObservedObject var glassesManager: GlassesCaptureManager
    @ObservedObject var alertsManager: NearbyAlertsManager

    @State private var step: Step = .welcome

    var body: some View {
        NavigationStack {
            ZStack {
                switch step {
                case .welcome:
                    WelcomeIntroView {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { step = .permissions }
                    }
                case .permissions:
                    PermissionsEnableView(alertsManager: alertsManager) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { step = .deviceCapability }
                    }
                case .deviceCapability:
                    DeviceCapabilityView {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { step = .tutorial }
                    }
                case .tutorial:
                    CaptureTutorialView {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { step = .connectGlasses }
                    }
                case .connectGlasses:
                    ConnectGlassesStepView(glassesManager: glassesManager) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { step = .complete }
                    }
                case .complete:
                    CompletionView {
                        isOnboarded = true
                        UserDeviceService.updateLocalUser(fields: ["finishedOnboarding": true])
                        AppSessionService.shared.log("onboardingComplete")
                    }
                }
            }
            .toolbar { ToolbarTitleContent(step: step) }
            .blueprintOnboardingBackground()
        }
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeIntroView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 72))
                    .foregroundStyle(BlueprintTheme.brandTeal)

                Text("Get paid to\nscan spaces")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("Scan indoor spaces with your iPhone, and get paid once quality review approves your capture.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Spacer()

            VStack(spacing: 14) {
                featureRow(icon: "bolt.fill", text: "One-tap scans from nearby alerts")
                featureRow(icon: "icloud.and.arrow.up", text: "Auto-upload after recording")
                featureRow(icon: "dollarsign.circle", text: "Paid after quality verification")
            }
            .padding(.horizontal, 28)

            Spacer()

            Button("Get Started", action: onContinue)
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

// MARK: - Step 2: Permissions (Camera, Notifications, Location)

private struct PermissionsEnableView: View {
    @ObservedObject var alertsManager: NearbyAlertsManager
    let onContinue: () -> Void

    @State private var cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var locationGranted: Bool = {
        let status = CLLocationManager().authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }()
    @State private var notificationsGranted = false
    @State private var motionGranted = MotionPermissionHelper.isAuthorized

    @State private var isRequesting = false
    @State private var showingPermissionAlert = false

    private let notificationService = NotificationService()

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(BlueprintTheme.brandTeal)

                Text("Enable Permissions")
                    .font(.title2.weight(.bold))

                Text("We use these to find nearby scan jobs and capture spatial data.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .padding(.top, 28)

            VStack(spacing: 12) {
                permissionRow(title: "Location", icon: "location.fill", granted: locationGranted)
                permissionRow(title: "Notifications", icon: "bell.fill", granted: notificationsGranted)
                permissionRow(title: "Camera", icon: "camera.fill", granted: cameraGranted)
                permissionRow(title: "Motion", icon: "figure.walk.motion", granted: motionGranted)
            }
            .padding(.horizontal, 24)

            Spacer()

            Button(action: enableAll) {
                if isRequesting {
                    ProgressView().tint(.white)
                } else {
                    Text("Enable")
                }
            }
            .buttonStyle(BlueprintPrimaryButtonStyle())
            .disabled(isRequesting)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .task {
            refreshStatuses()
        }
        .onChange(of: alertsManager.authorizationStatus) { _, _ in
            refreshStatuses()
        }
        .alert("Permissions Required", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Continue Anyway") { onContinue() }
        } message: {
            Text("Location and notifications are recommended for nearby alerts. Camera and motion access are required for capture.")
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

    private var requiredPermissionsGranted: Bool { cameraGranted && locationGranted && motionGranted }

    private func refreshStatuses() {
        cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let status = CLLocationManager().authorizationStatus
        locationGranted = status == .authorizedWhenInUse || status == .authorizedAlways
        motionGranted = MotionPermissionHelper.isAuthorized

        alertsManager.refreshNotificationStatus()
        notificationsGranted = alertsManager.notificationsGranted
    }

    private func enableAll() {
        isRequesting = true
        Task {
            let cam = await AVCaptureDevice.requestAccess(for: .video)
            UserDeviceService.setPermission("camera", granted: cam)

            alertsManager.requestWhenInUseAuthorization()
            UserDeviceService.setPermission("location", granted: alertsManager.isLocationAuthorized)

            let motion = await MotionPermissionHelper.requestAuthorization()
            UserDeviceService.setPermission("motion", granted: motion)

            await notificationService.requestAuthorizationIfNeeded()
            alertsManager.refreshNotificationStatus()
            UserDeviceService.setPermission("notifications", granted: alertsManager.notificationsGranted)

            await MainActor.run {
                refreshStatuses()
                isRequesting = false
                if requiredPermissionsGranted {
                    onContinue()
                } else {
                    showingPermissionAlert = true
                }
            }
        }
    }
}

// MARK: - Step 3: Connect Glasses (Required)

private struct ConnectGlassesStepView: View {
    @ObservedObject var glassesManager: GlassesCaptureManager
    let onContinue: () -> Void

    @State private var showingConnectSheet = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "eyeglasses")
                    .font(.system(size: 56))
                    .foregroundStyle(BlueprintTheme.brandTeal)

                Text("Connect Smart Glasses")
                    .font(.title2.weight(.bold))

                Text("Optional — pair Meta smart glasses for hands-free capture.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    showingConnectSheet = true
                } label: {
                    Text(connectionButtonTitle)
                }
                .buttonStyle(BlueprintPrimaryButtonStyle())

                if case .connected = glassesManager.connectionState {
                    Button("Continue", action: onContinue)
                        .buttonStyle(BlueprintSuccessButtonStyle())
                } else {
                    Button("Skip — Use iPhone Only", action: onContinue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showingConnectSheet) {
            GlassesConnectSheet(glassesManager: glassesManager) {
                showingConnectSheet = false
            }
        }
    }

    private var connectionButtonTitle: String {
        switch glassesManager.connectionState {
        case .connected:
            return "Manage Connection"
        case .connecting:
            return "Connecting…"
        case .scanning:
            return "Scanning…"
        case .error:
            return "Try Again"
        case .disconnected:
            return "Connect Glasses"
        }
    }
}

// MARK: - Step 4: Done

private struct CompletionView: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(BlueprintTheme.successGreen)

                Text("You're All Set")
                    .font(.title.weight(.bold))

                Text("We’ll notify you when curated scan jobs are nearby.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Spacer()

            Button("Start Scanning", action: onFinish)
                .buttonStyle(BlueprintPrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }
}

// MARK: - Toolbar title

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
        case .deviceCapability: return "Your Device"
        case .tutorial: return "How It Works"
        case .connectGlasses: return "Glasses"
        case .complete: return "All set"
        }
    }
}
