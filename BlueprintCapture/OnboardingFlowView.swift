import SwiftUI
import AVFoundation
import UserNotifications
import CoreLocation
import UIKit
import FirebaseAuth

/// Onboarding flow:
/// Welcome → Auth → Invite Code → Permissions → Device → Tutorial → Connect Glasses → Done
/// Auth comes before invite code so the code lookup can require authentication,
/// and the referral can be attributed immediately with the real user ID.
struct OnboardingFlowView: View {
    enum Step: Int, CaseIterable {
        case welcome, auth, inviteCode, permissions, deviceCapability, tutorial, connectGlasses, complete
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
            Color.clear.ignoresSafeArea()

            switch step {
            case .welcome:
                OnboardingWelcomeView(onContinue: advance)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case .auth:
                AuthStepView(onContinue: advance)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case .inviteCode:
                InviteCodeStepView(onContinue: advance)
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
                OnboardingCompleteView(glassesConnected: isGlassesConnected) {
                    isOnboarded = true
                    UserDeviceService.updateLocalUser(fields: ["finishedOnboarding": true])
                    AppSessionService.shared.log("onboardingComplete")
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            }
        }
        .blueprintOnboardingBackground()
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: step)
    }

    private var isGlassesConnected: Bool {
        if case .connected = glassesManager.connectionState {
            return true
        }
        return false
    }
}

// MARK: - Step 1: Welcome

private struct OnboardingWelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("BlueprintCapture")
                        .font(BlueprintTheme.body(12, weight: .semibold))
                        .tracking(2.4)
                        .foregroundStyle(BlueprintTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 28)

                    Text("Contributor Onboarding")
                        .font(BlueprintTheme.display(34, weight: .semibold))
                        .foregroundStyle(BlueprintTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 20)

                heroCard
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)

                VStack(alignment: .leading, spacing: 12) {
                    featureRow(icon: "location.viewfinder", text: "Nearby spaces and approved opportunities")
                    featureRow(icon: "hand.raised.fill", text: "Rights and policy checks before reuse")
                    featureRow(icon: "cube.transparent", text: "Truthful capture feeds downstream world models")
                }
                .padding(.horizontal, 28)

                Spacer(minLength: 16)

                kledPrimaryButton("Get Started", action: onContinue)
                    .accessibilityIdentifier("onboarding-get-started")
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
    }

    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            Image("OnboardingHero")
                .resizable()
                .aspectRatio(contentMode: .fill)

            LinearGradient(
                colors: [Color.black.opacity(0.08), Color.black.opacity(0.24), Color.black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    Image(systemName: "camera.metering.matrix")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textSecondary)
                        .padding(14)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Get paid\nto scan spaces")
                        .font(BlueprintTheme.display(28, weight: .semibold))
                        .foregroundStyle(BlueprintTheme.textPrimary)

                    Rectangle()
                        .fill(BlueprintTheme.hairline)
                        .frame(width: 58, height: 1)

                    Text("Capture real places.\nProvide truthful data.\nPower world models.")
                        .font(BlueprintTheme.body(16, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }
        }
        .frame(height: 420)
        .blueprintEditorialCard(radius: 34, fill: BlueprintTheme.panel)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BlueprintTheme.textPrimary)
                .frame(width: 24)

            Text(text)
                .font(BlueprintTheme.body(14, weight: .medium))
                .foregroundStyle(BlueprintTheme.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .blueprintPanelBackground(radius: 16, fill: BlueprintTheme.panelMuted)
    }
}

// MARK: - Step 3: Invite Code (shown after auth)

private struct InviteCodeStepView: View {
    let onContinue: () -> Void

    @AppStorage(PendingReferralStore.storageKey) private var pendingReferralCode: String = ""
    @State private var codeInput: String = ""
    @State private var validationError: String? = nil
    @State private var isValidating = false

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with skip
                HStack {
                    Spacer()
                    Button("Skip for now") { onContinue() }
                        .font(BlueprintTheme.body(14, weight: .semibold))
                        .foregroundStyle(BlueprintTheme.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 32)

                VStack(spacing: 14) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(BlueprintTheme.textPrimary)

                    Text("Got an Invite?")
                        .font(BlueprintTheme.display(28, weight: .semibold))
                        .foregroundStyle(BlueprintTheme.textPrimary)

                    Text("Enter your friend's invite code below.\nYou'll both get 10% extra on your first payout.")
                        .font(BlueprintTheme.body(15, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                .padding(.bottom, 36)

                // Code input
                VStack(alignment: .leading, spacing: 8) {
                    Text("INVITE CODE")
                        .font(BlueprintTheme.body(12, weight: .bold))
                        .foregroundStyle(BlueprintTheme.textTertiary)
                        .tracking(1.0)

                    TextField("e.g. AB12CD", text: $codeInput)
                        .font(.title3.weight(.bold).monospaced())
                        .foregroundStyle(.white)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .tint(BlueprintTheme.brandTeal)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(BlueprintTheme.panelStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    validationError != nil ? Color.white.opacity(0.35) : BlueprintTheme.hairline,
                                    lineWidth: 1
                                )
                        )
                        .onChange(of: codeInput) { _, newValue in
                            validationError = nil
                            if newValue.count > 6 {
                                codeInput = String(newValue.prefix(6))
                            }
                        }
                        .onAppear {
                            // Pre-fill from a deep link (?ref=CODE) that was captured before auth.
                            let pending = pendingReferralCode.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !pending.isEmpty, codeInput.isEmpty {
                                codeInput = pending
                            }
                        }

                    if let err = validationError {
                        Text(err)
                            .font(BlueprintTheme.body(12, weight: .medium))
                            .foregroundStyle(BlueprintTheme.textSecondary)
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
                                .font(BlueprintTheme.body(16, weight: .semibold))
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        codeInput.trimmingCharacters(in: .whitespaces).isEmpty ? Color.white.opacity(0.32) : Color.white,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
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
        isValidating = true
        Task {
            do {
                // Auth comes before this step, so we can attribute the referral
                // immediately rather than deferring to sign-up.
                if let currentUser = FirebaseAuth.Auth.auth().currentUser {
                    let name = currentUser.displayName ?? currentUser.email ?? "Capturer"
                    let result = try await ReferralService.shared.attributeReferral(
                        code: normalized,
                        newUserId: currentUser.uid,
                        newUserName: name
                    )
                    await MainActor.run {
                        isValidating = false
                        switch result {
                        case .attributed:
                            pendingReferralCode = ""
                            onContinue()
                        case .invalidCode:
                            validationError = "Code not found. Double-check with your friend and try again."
                        case .selfReferral:
                            validationError = "You can't use your own invite code."
                        case .alreadyAttributed:
                            // Already referred — just advance
                            pendingReferralCode = ""
                            onContinue()
                        }
                    }
                } else {
                    // Fallback: user somehow not signed in yet — validate code exists
                    // and store for attribution after sign-up.
                    let ownerId = try await ReferralService.shared.findUserByReferralCode(normalized)
                    await MainActor.run {
                        isValidating = false
                        if ownerId != nil {
                            pendingReferralCode = normalized
                            onContinue()
                        } else {
                            validationError = "Code not found. Double-check with your friend and try again."
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isValidating = false
                    validationError = "Couldn't verify code. Check your connection and try again."
                }
            }
        }
    }
}

// MARK: - Step 3: Auth (Sign In / Create Account)

private struct AuthStepView: View {
    let onContinue: () -> Void

    @StateObject private var vm = AuthViewModel()
    @FocusState private var focusedField: AuthFocusField?

    enum AuthFocusField: Hashable { case name, email, password, confirmPassword }

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Top bar
                    HStack {
                        Spacer()
                        Button("Skip for now") { onContinue() }
                            .font(BlueprintTheme.body(14, weight: .semibold))
                            .foregroundStyle(BlueprintTheme.textSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    .padding(.bottom, 28)

                    // Title
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Create your account")
                            .font(BlueprintTheme.display(34, weight: .semibold))
                            .foregroundStyle(BlueprintTheme.textPrimary)
                        Text("Sign up to track earnings and get paid.")
                            .font(BlueprintTheme.body(15, weight: .medium))
                            .foregroundStyle(BlueprintTheme.textSecondary)
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
                            .background(BlueprintTheme.panelStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(BlueprintTheme.hairline, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("auth-google")

                        // Divider
                        HStack(spacing: 12) {
                            Rectangle().fill(Color(white: 0.15)).frame(height: 1)
                            Text("or")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(BlueprintTheme.textTertiary)
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
                                .accessibilityIdentifier(mode == .signIn ? "auth-sign-in" : "auth-create-account")
                            }
                        }
                        .padding(4)
                        .background(BlueprintTheme.panelMuted, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(BlueprintTheme.hairline, lineWidth: 1)
                        )

                        // Fields
                        if vm.mode == .signUp {
                            authTextField("Full Name", placeholder: "John Doe", text: $vm.name,
                                          icon: "person.fill", focusBinding: $focusedField,
                                          focusValue: .name, submitLabel: .next) { focusedField = .email }
                        }
                        authTextField("Email Address", placeholder: "you@example.com", text: $vm.email,
                                      icon: "envelope.fill", keyboardType: .emailAddress,
                                      focusBinding: $focusedField, focusValue: .email, submitLabel: .next,
                                      accessibilityIdentifier: "auth-email") { focusedField = .password }

                        AuthSecureFieldView(title: "Password", placeholder: "At least 8 characters",
                                            text: $vm.password, focusBinding: $focusedField, focusValue: .password,
                                            submitLabel: vm.mode == .signUp ? .next : .go) {
                            if vm.mode == .signUp { focusedField = .confirmPassword }
                            else { Task { await vm.submit() } }
                        }

                        if vm.mode == .signUp {
                            AuthSecureFieldView(title: "Confirm Password", placeholder: "Re-enter your password",
                                                text: $vm.confirmPassword, focusBinding: $focusedField,
                                                focusValue: .confirmPassword, submitLabel: .go) { Task { await vm.submit() } }
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
                                Color.white.opacity(0.06),
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
                                vm.canSubmit ? Color.white : Color.white.opacity(0.28),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
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
    }

    private func authTextField(
        _ title: String,
        placeholder: String,
        text: Binding<String>,
        icon: String,
        keyboardType: UIKeyboardType = .default,
        focusBinding: FocusState<AuthFocusField?>.Binding,
        focusValue: AuthFocusField,
        submitLabel: SubmitLabel = .next,
        accessibilityIdentifier: String? = nil,
        onSubmit: @escaping () -> Void = {}
    ) -> some View {
        let focused = focusBinding.wrappedValue == focusValue
        return VStack(alignment: .leading, spacing: 6) {
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
                    .focused(focusBinding, equals: focusValue)
                    .submitLabel(submitLabel)
                    .onSubmit(onSubmit)
                    .accessibilityIdentifier(accessibilityIdentifier ?? "")
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
    var focusBinding: FocusState<AuthStepView.AuthFocusField?>.Binding
    let focusValue: AuthStepView.AuthFocusField
    let submitLabel: SubmitLabel
    let onSubmit: () -> Void
    @State private var visible = false

    var focused: Bool { focusBinding.wrappedValue == focusValue }

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
                        .focused(focusBinding, equals: focusValue)
                        .submitLabel(submitLabel)
                        .onSubmit(onSubmit)
                } else {
                    SecureField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .foregroundStyle(.white)
                        .tint(BlueprintTheme.brandTeal)
                        .focused(focusBinding, equals: focusValue)
                        .submitLabel(submitLabel)
                        .onSubmit(onSubmit)
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
            Color.clear.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(BlueprintTheme.textPrimary)

                    Text("Enable Permissions")
                        .font(BlueprintTheme.display(30, weight: .semibold))
                        .foregroundStyle(BlueprintTheme.textPrimary)

                    Text("We use these to find nearby spaces, capture stronger evidence, and keep review states up to date.")
                        .font(BlueprintTheme.body(15, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textSecondary)
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
                .font(BlueprintTheme.body(15, weight: .semibold))
                .foregroundStyle(BlueprintTheme.textPrimary)

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
                        .stroke(BlueprintTheme.hairline, lineWidth: 1)
                )
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
            let location = await LocationPermissionRequester.requestWhenInUse()
            UserDeviceService.setPermission("location", granted: location)
            let motion = await MotionPermissionHelper.requestAuthorization()
            UserDeviceService.setPermission("motion", granted: motion)
            await notificationService.requestAuthorizationIfNeeded()
            alertsManager.refreshNotificationStatus()
            await MainActor.run {
                refreshStatuses()
                UserDeviceService.setPermission("notifications", granted: notificationsGranted)
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
            Color.clear.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 56))
                        .foregroundStyle(BlueprintTheme.textPrimary)

                    Text("Connect Smart Glasses")
                        .font(BlueprintTheme.display(30, weight: .semibold))
                        .foregroundStyle(BlueprintTheme.textPrimary)

                    Text("Pair Meta smart glasses for hands-free capture, or skip and start with your iPhone.")
                        .font(BlueprintTheme.body(15, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                .padding(.bottom, 36)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        Image(systemName: "wave.3.right")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(BlueprintTheme.textPrimary)
                            .frame(width: 42, height: 42)
                            .background(BlueprintTheme.panelStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Connect once")
                                .font(BlueprintTheme.body(15, weight: .semibold))
                                .foregroundStyle(BlueprintTheme.textPrimary)
                            Text("Then move straight into hands-free capture whenever a site opens.")
                                .font(BlueprintTheme.body(13, weight: .medium))
                                .foregroundStyle(BlueprintTheme.textSecondary)
                        }

                        Spacer()
                    }
                }
                .padding(18)
                .padding(.horizontal, 24)
                .blueprintEditorialCard(radius: 20, fill: BlueprintTheme.panel)

                Spacer()

                VStack(spacing: 12) {
                    if case .connected = glassesManager.connectionState {
                        kledPrimaryButton("Continue", action: onContinue)
                    } else {
                        kledPrimaryButton(connectionButtonTitle) {
                            showConnectSheet = true
                        }

                        Button("Skip — Use iPhone Only", action: onContinue)
                            .font(BlueprintTheme.body(14, weight: .semibold))
                            .foregroundStyle(BlueprintTheme.textSecondary)
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
        case .registering: return "Connecting…"
        case .waitingForDevice: return "Waiting for Glasses"
        case .permissionRequired: return "Grant Permission"
        case .error: return "Try Again"
        case .disconnected: return "Connect Glasses"
        }
    }
}

// MARK: - Step 8: Complete

private struct OnboardingCompleteView: View {
    let glassesConnected: Bool
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(BlueprintTheme.textPrimary)

                    Text(OnboardingCaptureUXCopy.completionTitle(glassesConnected: glassesConnected))
                        .font(BlueprintTheme.display(30, weight: .semibold))
                        .foregroundStyle(BlueprintTheme.textPrimary)

                    Text(OnboardingCaptureUXCopy.completionMessage(glassesConnected: glassesConnected))
                        .font(BlueprintTheme.body(16, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textSecondary)
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
