import SwiftUI
import AVFoundation
import UserNotifications
import CoreLocation
import UIKit
import FirebaseAuth

/// Onboarding flow — Kled AI style:
/// Welcome → Invite Code → Auth → Permissions → Device → Tutorial → Connect Glasses → Done
struct OnboardingFlowView: View {
    enum Step: Int, CaseIterable {
        case welcome, inviteCode, auth, permissions, deviceCapability, tutorial, connectGlasses, complete
    }

    @AppStorage("com.blueprint.isOnboarded") private var isOnboarded: Bool = false

    @ObservedObject var glassesManager: GlassesCaptureManager
    @ObservedObject var alertsManager: NearbyAlertsManager

    @State private var step: Step = .welcome

    private func advance() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            guard let next = Step(rawValue: step.rawValue + 1) else { return }
            step = next
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch step {
            case .welcome:
                OnboardingWelcomeView(onContinue: advance)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case .inviteCode:
                InviteCodeStepView(onContinue: advance)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case .auth:
                AuthStepView(onContinue: advance)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case .permissions:
                OnboardingPermissionsView(alertsManager: alertsManager, onContinue: advance)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case .deviceCapability:
                DeviceCapabilityView(onContinue: advance)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case .tutorial:
                CaptureTutorialView(onContinue: advance)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case .connectGlasses:
                OnboardingGlassesView(glassesManager: glassesManager, onContinue: advance)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case .complete:
                OnboardingCompleteView {
                    isOnboarded = true
                    UserDeviceService.updateLocalUser(fields: ["finishedOnboarding": true])
                    AppSessionService.shared.log("onboardingComplete")
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            }
        }
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: step)
    }
}

// MARK: - Step 1: Welcome

private struct OnboardingWelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 72))
                        .foregroundStyle(BlueprintTheme.brandTeal)

                    Text("Get paid to\nscan spaces")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("Capture spaces for Blueprint review. We check rights, coverage, and quality before anything moves downstream.")
                        .font(.body)
                        .foregroundStyle(Color(white: 0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                Spacer()

                VStack(spacing: 12) {
                    featureRow(icon: "location.viewfinder", text: "Nearby spaces and approved opportunities")
                    featureRow(icon: "hand.raised.fill", text: "Rights and policy checks before reuse")
                    featureRow(icon: "dollarsign.circle", text: "Payout only after review approval")
                }
                .padding(.horizontal, 28)

                Spacer()

                kledPrimaryButton("Get Started", action: onContinue)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(BlueprintTheme.brandTeal)
                .frame(width: 24)

            Text(text)
                .font(.body)
                .foregroundStyle(Color(white: 0.55))

            Spacer()
        }
    }
}

// MARK: - Step 2: Invite Code

private struct InviteCodeStepView: View {
    let onContinue: () -> Void

    @AppStorage(PendingReferralStore.storageKey) private var pendingReferralCode: String = ""
    @State private var codeInput: String = ""
    @State private var validationError: String? = nil
    @State private var isValidating = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with skip
                HStack {
                    Spacer()
                    Button("Skip for now") { onContinue() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(white: 0.5))
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 32)

                VStack(spacing: 16) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(BlueprintTheme.brandTeal)

                    Text("Got an Invite?")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Enter your friend's invite code below.\nYou'll both get 10% extra on your first payout.")
                        .font(.subheadline)
                        .foregroundStyle(Color(white: 0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                .padding(.bottom, 36)

                // Code input
                VStack(alignment: .leading, spacing: 8) {
                    Text("INVITE CODE")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(white: 0.35))
                        .tracking(1.0)

                    TextField("e.g. AB12CD", text: $codeInput)
                        .font(.title3.weight(.bold).monospaced())
                        .foregroundStyle(.white)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .tint(BlueprintTheme.brandTeal)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    validationError != nil ? Color(red: 0.95, green: 0.35, blue: 0.35).opacity(0.6) : Color(white: 0.18),
                                    lineWidth: 1
                                )
                        )
                        .onChange(of: codeInput) { _, _ in validationError = nil }

                    if let err = validationError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(Color(red: 0.95, green: 0.35, blue: 0.35))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                // Submit
                Button {
                    submitCode()
                } label: {
                    Group {
                        if isValidating {
                            ProgressView().tint(.black).controlSize(.small)
                        } else {
                            Text("Apply Code")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        codeInput.trimmingCharacters(in: .whitespaces).isEmpty ? Color(white: 0.2) : Color.white,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(codeInput.trimmingCharacters(in: .whitespaces).isEmpty || isValidating)
                .padding(.horizontal, 24)

                Spacer()
            }
        }
    }

    private func submitCode() {
        let raw = codeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized = ReferralService.normalizedReferralCode(raw) else {
            validationError = "Invalid code — must be 6 characters (A-Z, 0-9)."
            return
        }
        pendingReferralCode = normalized
        onContinue()
    }
}

// MARK: - Step 3: Auth (Sign In / Create Account)

private struct AuthStepView: View {
    let onContinue: () -> Void

    @StateObject private var vm = AuthViewModel()
    @FocusState private var focusedField: AuthFocusField?

    enum AuthFocusField { case name, email, password, confirmPassword }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Top bar
                    HStack {
                        Spacer()
                        Button("Skip for now") { onContinue() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(white: 0.5))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    .padding(.bottom, 28)

                    // Title
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Create your account")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Sign up to track earnings and get paid.")
                            .font(.subheadline)
                            .foregroundStyle(Color(white: 0.45))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)

                    VStack(spacing: 14) {
                        // Google
                        Button {
                            Task { await vm.signInWithGoogle() }
                        } label: {
                            HStack(spacing: 12) {
                                GoogleLogo(size: 18)
                                Text("Continue with Google")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .frame(maxWidth: .infinity)
                            .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color(white: 0.18), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        // Divider
                        HStack(spacing: 12) {
                            Rectangle().fill(Color(white: 0.15)).frame(height: 1)
                            Text("or")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color(white: 0.4))
                            Rectangle().fill(Color(white: 0.15)).frame(height: 1)
                        }
                        .padding(.vertical, 2)

                        // Mode toggle
                        HStack(spacing: 6) {
                            ForEach([AuthViewModel.Mode.signUp, .signIn], id: \.self) { mode in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { vm.mode = mode }
                                } label: {
                                    Text(mode == .signIn ? "Sign In" : "Create Account")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(vm.mode == mode ? .white : Color(white: 0.45))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                        .background(
                                            vm.mode == mode ? Color(white: 0.18) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(4)
                        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(white: 0.12), lineWidth: 1)
                        )

                        // Fields
                        if vm.mode == .signUp {
                            authTextField("Full Name", placeholder: "John Doe", text: $vm.name,
                                          icon: "person.fill", focused: focusedField == .name)
                            .onTapGesture { focusedField = .name }
                        }
                        authTextField("Email Address", placeholder: "you@example.com", text: $vm.email,
                                      icon: "envelope.fill", keyboardType: .emailAddress, focused: focusedField == .email)
                        .onTapGesture { focusedField = .email }

                        AuthSecureFieldView(title: "Password", placeholder: "At least 8 characters",
                                            text: $vm.password, focused: focusedField == .password)
                        .onTapGesture { focusedField = .password }

                        if vm.mode == .signUp {
                            AuthSecureFieldView(title: "Confirm Password", placeholder: "Re-enter your password",
                                                text: $vm.confirmPassword, focused: focusedField == .confirmPassword)
                            .onTapGesture { focusedField = .confirmPassword }
                        }

                        // Error
                        if let err = vm.errorMessage, !err.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill").font(.caption)
                                Text(err).font(.caption)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(Color(red: 0.95, green: 0.35, blue: 0.35))
                            .padding(12)
                            .background(
                                Color(red: 0.95, green: 0.35, blue: 0.35).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        }

                        // Submit
                        Button {
                            Task { await vm.submit() }
                        } label: {
                            Group {
                                if vm.isBusy {
                                    ProgressView().tint(.black).controlSize(.small)
                                } else {
                                    Text(vm.mode == .signIn ? "Sign In" : "Create Account")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.black)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                vm.canSubmit ? Color.white : Color(white: 0.25),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!vm.canSubmit)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 48)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AuthStateDidChange)) { _ in
            onContinue()
        }
        .task {
            vm.consumePasteboardReferralIfNeeded()
        }
    }

    private func authTextField(
        _ title: String,
        placeholder: String,
        text: Binding<String>,
        icon: String,
        keyboardType: UIKeyboardType = .default,
        focused: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(white: 0.6))

            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(focused ? BlueprintTheme.brandTeal : Color(white: 0.4))
                    .frame(width: 20)

                TextField(placeholder, text: text)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .foregroundStyle(.white)
                    .tint(BlueprintTheme.brandTeal)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        focused ? BlueprintTheme.brandTeal.opacity(0.6) : Color(white: 0.18),
                        lineWidth: focused ? 1.5 : 1
                    )
            )
        }
    }
}

private struct AuthSecureFieldView: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let focused: Bool
    @State private var visible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(white: 0.6))

            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(focused ? BlueprintTheme.brandTeal : Color(white: 0.4))
                    .frame(width: 20)

                if visible {
                    TextField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .foregroundStyle(.white)
                        .tint(BlueprintTheme.brandTeal)
                } else {
                    SecureField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .foregroundStyle(.white)
                        .tint(BlueprintTheme.brandTeal)
                }

                Button { visible.toggle() } label: {
                    Image(systemName: visible ? "eye.slash.fill" : "eye.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(white: 0.4))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        focused ? BlueprintTheme.brandTeal.opacity(0.6) : Color(white: 0.18),
                        lineWidth: focused ? 1.5 : 1
                    )
            )
        }
    }
}

// MARK: - Step 4: Permissions

private struct OnboardingPermissionsView: View {
    @ObservedObject var alertsManager: NearbyAlertsManager
    let onContinue: () -> Void

    @State private var cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var locationGranted: Bool = {
        let s = CLLocationManager().authorizationStatus
        return s == .authorizedWhenInUse || s == .authorizedAlways
    }()
    @State private var notificationsGranted = false
    @State private var motionGranted = MotionPermissionHelper.isAuthorized
    @State private var isRequesting = false
    @State private var showAlert = false

    private let notificationService = NotificationService()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(BlueprintTheme.brandTeal)

                    Text("Enable Permissions")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Text("We use these to find nearby spaces, capture stronger evidence, and keep review states up to date.")
                        .font(.subheadline)
                        .foregroundStyle(Color(white: 0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                .padding(.bottom, 32)

                VStack(spacing: 10) {
                    permRow(title: "Location", icon: "location.fill", granted: locationGranted)
                    permRow(title: "Notifications", icon: "bell.fill", granted: notificationsGranted)
                    permRow(title: "Camera", icon: "camera.fill", granted: cameraGranted)
                    permRow(title: "Motion", icon: "figure.walk.motion", granted: motionGranted)
                }
                .padding(.horizontal, 24)

                Spacer()

                kledPrimaryButton(
                    isRequesting ? "" : "Enable",
                    loading: isRequesting,
                    action: enableAll
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .task { refreshStatuses() }
        .onChange(of: alertsManager.authorizationStatus) { _, _ in refreshStatuses() }
        .alert("Permissions Required", isPresented: $showAlert) {
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

    private func permRow(title: String, icon: String, granted: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(granted ? BlueprintTheme.successGreen : Color(white: 0.45))
                .frame(width: 36, height: 36)
                .background(
                    (granted ? BlueprintTheme.successGreen : Color(white: 0.25)).opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(granted ? BlueprintTheme.successGreen : Color(white: 0.3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
    }

    private var requiredGranted: Bool { cameraGranted && locationGranted && motionGranted }

    private func refreshStatuses() {
        cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let s = CLLocationManager().authorizationStatus
        locationGranted = s == .authorizedWhenInUse || s == .authorizedAlways
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
                if requiredGranted { onContinue() } else { showAlert = true }
            }
        }
    }
}

// MARK: - Step 7: Connect Glasses

private struct OnboardingGlassesView: View {
    @ObservedObject var glassesManager: GlassesCaptureManager
    let onContinue: () -> Void

    @State private var showConnectSheet = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 56))
                        .foregroundStyle(BlueprintTheme.brandTeal)

                    Text("Connect Smart Glasses")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Optional — pair Meta smart glasses for hands-free capture.")
                        .font(.subheadline)
                        .foregroundStyle(Color(white: 0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                .padding(.bottom, 36)

                Spacer()

                VStack(spacing: 12) {
                    if case .connected = glassesManager.connectionState {
                        kledPrimaryButton("Continue", action: onContinue)
                    } else {
                        kledPrimaryButton(connectionButtonTitle) {
                            showConnectSheet = true
                        }

                        Button("Skip — Use iPhone Only", action: onContinue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(white: 0.45))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showConnectSheet) {
            GlassesConnectSheet(glassesManager: glassesManager) {
                showConnectSheet = false
            }
        }
    }

    private var connectionButtonTitle: String {
        switch glassesManager.connectionState {
        case .connected: return "Manage Connection"
        case .connecting: return "Connecting…"
        case .scanning: return "Scanning…"
        case .error: return "Try Again"
        case .disconnected: return "Connect Glasses"
        }
    }
}

// MARK: - Step 8: Complete

private struct OnboardingCompleteView: View {
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(BlueprintTheme.successGreen)

                    Text("You're All Set")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)

                    Text("We'll notify you when approved capture opportunities are nearby.")
                        .font(.body)
                        .foregroundStyle(Color(white: 0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                Spacer()

                kledPrimaryButton("Start Capturing", action: onFinish)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Kled primary button helper

@ViewBuilder
private func kledPrimaryButton(
    _ label: String,
    loading: Bool = false,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        Group {
            if loading {
                ProgressView().tint(.black).controlSize(.small)
            } else {
                Text(label)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(loading)
}
