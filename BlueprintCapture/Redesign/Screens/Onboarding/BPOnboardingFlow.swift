import SwiftUI
import Combine
import AVFoundation
import CoreLocation
import UserNotifications
import UIKit

// MARK: - BPOnboardingFlow
//
// First-run induction after a real account exists: how Blueprint works, where
// you can capture (launch-city status), the permissions the field instrument
// needs, rights & privacy certification, and payout setup. Every step is
// honest-state driven — nothing asserts readiness the backend hasn't granted —
// and the whole flow is skippable; the Home setup checklist picks up whatever
// was skipped.

struct BPOnboardingStateMachine: Equatable {
    enum Step: Int, CaseIterable, Equatable {
        case welcome
        case city
        case permissions
        case rights
        case payouts

        var eyebrow: String {
            switch self {
            case .welcome: return "How it works"
            case .city: return "Where you capture"
            case .permissions: return "Field permissions"
            case .rights: return "Rights & privacy"
            case .payouts: return "Getting paid"
            }
        }
    }

    private(set) var step: Step = .welcome

    init(step: Step = .welcome) {
        self.step = step
    }

    var index: Int { step.rawValue }
    var count: Int { Step.allCases.count }
    var isFirst: Bool { step == .welcome }
    var isLast: Bool { step == Step.allCases.last }

    /// Advances to the next step; returns false when the flow is finished.
    @discardableResult
    mutating func advance() -> Bool {
        guard let next = Step(rawValue: step.rawValue + 1) else { return false }
        step = next
        return true
    }

    /// Steps back; returns false when already on the first step.
    @discardableResult
    mutating func goBack() -> Bool {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return false }
        step = previous
        return true
    }
}

// MARK: - Flow root

struct BPOnboardingFlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var coordinator: RedesignCoordinator
    @ObservedObject private var capturerState = BPCapturerStateStore.shared

    @State private var machine: BPOnboardingStateMachine
    @State private var cityGate = LaunchCityGateViewModel()
    @StateObject private var permissions = BPPermissionsModel()

    init(initialStep: BPOnboardingStateMachine.Step = .welcome) {
        _machine = State(initialValue: BPOnboardingStateMachine(step: initialStep))
    }

    var body: some View {
        VStack(spacing: 0) {
            BPOnboardingProgressHeader(
                machine: machine,
                onBack: { withAnimation(stepAnimation) { _ = machine.goBack() } },
                onSkip: finish
            )

            Group {
                switch machine.step {
                case .welcome:
                    BPOnboardingWelcomeStep(onContinue: advance)
                case .city:
                    BPOnboardingCityStep(gate: cityGate, onContinue: advance)
                case .permissions:
                    BPOnboardingPermissionsStep(model: permissions, onContinue: advance)
                case .rights:
                    BPOnboardingRightsStep(
                        onCertified: {
                            capturerState.certifyRights()
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            advance()
                        },
                        onLater: advance
                    )
                case .payouts:
                    BPOnboardingPayoutStep(onDone: finish)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(stepTransition)
            .id(machine.step)
        }
        .background(BP.canvas.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onChange(of: cityGate.resolvedCity?.displayName) { _, newValue in
            if let newValue { coordinator.updateCity(newValue) }
        }
    }

    private var stepAnimation: Animation? {
        reduceMotion ? nil : BPMotion.transition
    }

    private var stepTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    private func advance() {
        withAnimation(stepAnimation) {
            if !machine.advance() { finish() }
        }
    }

    private func finish() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        capturerState.completeOnboarding()
    }
}

// MARK: - Progress header (step dots, webapp StepDots pattern in BP chrome)

struct BPOnboardingProgressHeader: View {
    let machine: BPOnboardingStateMachine
    var onBack: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: Space.s) {
            ZStack {
                stepDots
                HStack {
                    if !machine.isFirst {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(BP.textStrong)
                                .frame(width: 44, height: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Back")
                    }
                    Spacer()
                    Button("Skip", action: onSkip)
                        .font(.bpSans(BPType.bodyS, .semibold))
                        .foregroundStyle(BP.textMuted)
                        .frame(height: 44)
                        .accessibilityHint("Finish setup later from the Home checklist")
                }
            }
            .frame(height: 44)
            .padding(.horizontal, Space.l)

            Text("STEP \(machine.index + 1) OF \(machine.count) · \(machine.step.eyebrow.uppercased())")
                .font(.bpMono(BPType.micro))
                .tracking(BPTracking.eyebrow)
                .foregroundStyle(BP.textMuted)
                .accessibilityLabel("Step \(machine.index + 1) of \(machine.count): \(machine.step.eyebrow)")
        }
        .padding(.bottom, Space.s)
        .background(BP.canvas)
        .overlay(alignment: .bottom) { BPDivider(color: BP.lineSoft) }
    }

    private var stepDots: some View {
        HStack(spacing: 0) {
            ForEach(0..<machine.count, id: \.self) { idx in
                Circle()
                    .fill(idx <= machine.index ? BP.brass : BP.sunken)
                    .overlay(Circle().strokeBorder(idx <= machine.index ? BP.brassDeep.opacity(0.45) : BP.lineStrong, lineWidth: 1))
                    .frame(width: 10, height: 10)
                if idx < machine.count - 1 {
                    Rectangle()
                        .fill(idx < machine.index ? BP.brass : BP.line)
                        .frame(width: 22, height: 1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Shared step scaffold

private struct BPOnboardingStepScaffold<Content: View, Actions: View>: View {
    let headline: String
    var subhead: String? = nil
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text(headline)
                            .font(.bpDisplay(26))
                            .foregroundStyle(BP.textStrong)
                            .fixedSize(horizontal: false, vertical: true)
                        if let subhead {
                            Text(subhead)
                                .font(.bpSans(BPType.body, .regular))
                                .foregroundStyle(BP.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    content()
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.xl)
                .padding(.bottom, Space.l)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: Space.s) {
                actions()
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.m)
            .padding(.bottom, Space.s)
            .background(BP.canvas)
            .overlay(alignment: .top) { BPDivider(color: BP.lineSoft) }
        }
    }
}

// MARK: - Step 1 · Welcome / how it works

struct BPOnboardingWelcomeStep: View {
    @EnvironmentObject private var coordinator: RedesignCoordinator
    var onContinue: () -> Void

    var body: some View {
        BPOnboardingStepScaffold(
            headline: welcomeHeadline,
            subhead: "Blueprint pays for truthful, review-accepted capture of real facilities. Here's the whole loop."
        ) {
            BPHowItWorksSteps()
        } actions: {
            BPPrimaryButton(title: "Set up my kit", systemImage: "arrow.right") { onContinue() }
        }
    }

    private var welcomeHeadline: String {
        coordinator.capturerName.isEmpty
            ? "You're in."
            : "You're in, \(coordinator.capturerName)."
    }
}

// MARK: - Step 2 · Launch-city status

struct BPOnboardingCityStep: View {
    @Environment(\.openURL) private var openURL
    var gate: LaunchCityGateViewModel
    var onContinue: () -> Void

    var body: some View {
        BPOnboardingStepScaffold(
            headline: "Where you capture matters.",
            subhead: "Blueprint launches city by city. Your city sets which assignments you see — open capture stays available as review-gated evidence."
        ) {
            statusCard
            if case .supported = gate.state {} else if !gate.supportedCities.isEmpty {
                liveCitiesCard
            }
        } actions: {
            switch gate.state {
            case .locationPermissionRequired:
                BPPrimaryButton(title: "Share location", systemImage: "location") {
                    Task { await gate.requestLocationAccess() }
                }
                BPGhostButton(title: "Not now") { onContinue() }
            case .locationPermissionDenied:
                BPPrimaryButton(title: "Open Settings", systemImage: "gearshape") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                BPGhostButton(title: "Continue without location") { onContinue() }
            case .failed:
                BPPrimaryButton(title: "Try again", systemImage: "arrow.clockwise") { gate.refresh() }
                BPGhostButton(title: "Continue") { onContinue() }
            case .checking:
                BPGhostButton(title: "Continue") { onContinue() }
            case .supported, .unsupported:
                BPPrimaryButton(title: "Continue", systemImage: "arrow.right") { onContinue() }
            }
        }
        .onAppear { gate.start() }
    }

    @ViewBuilder
    private var statusCard: some View {
        switch gate.state {
        case .checking:
            BPCard {
                HStack(spacing: Space.m) {
                    ProgressView().controlSize(.small)
                    Text("Checking your city against the launch program…")
                        .font(.bpSans(BPType.body, .regular))
                        .foregroundStyle(BP.textMuted)
                }
            }
        case .locationPermissionRequired:
            infoCard(
                chip: BPChip(label: "Location needed", signal: .info),
                title: "Share your location once",
                body: "Blueprint uses your city to check launch status and to surface assignments near you. Location is only recorded inside capture bundles you choose to upload."
            )
        case .locationPermissionDenied:
            infoCard(
                chip: BPChip(label: "Location off", signal: .caution),
                title: "Location access is off",
                body: "Without location, nearby assignments and launch-city checks are unavailable. You can enable it any time in Settings."
            )
        case .supported(let city):
            infoCard(
                chip: BPChip(label: "Live city", signal: .proof),
                title: city.displayName,
                body: "\(city.displayName) is in the active launch program. Assignments here show payout before you start."
            )
        case .unsupported(let city):
            infoCard(
                chip: BPChip(label: "Review-gated", signal: .info),
                title: city?.displayName ?? "Outside launch cities",
                body: "This city is outside the active launch program, but truthful open capture can still proceed as review-gated evidence. Request launch access for operator-approved work.",
                extraAction: ("Request launch access", {
                    openURL(LaunchCityGateRecoveryDestination.requestURL(
                        mainWebsiteURL: AppConfig.mainWebsiteURL(),
                        helpCenterURL: AppConfig.helpCenterURL(),
                        supportEmailURL: AppConfig.supportEmailURL(subject: "Request launch access"),
                        resolvedCity: gate.resolvedCity
                    ))
                })
            )
        case .failed(let message):
            infoCard(
                chip: BPChip(label: "Check failed", signal: .caution),
                title: "Couldn't verify your city",
                body: message
            )
        }
    }

    private var liveCitiesCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            BPEyebrow("Live capture markets")
            BPCard(padding: Space.m) {
                FlowChips(labels: gate.supportedCities.map(\.displayName))
            }
        }
    }

    private func infoCard(
        chip: BPChip,
        title: String,
        body bodyText: String,
        extraAction: (String, () -> Void)? = nil
    ) -> some View {
        BPCard {
            VStack(alignment: .leading, spacing: Space.m) {
                BPStatusChip(chip.label, signal: chip.signal)
                Text(title)
                    .font(.bpSans(BPType.bodyL, .semibold))
                    .foregroundStyle(BP.textStrong)
                Text(bodyText)
                    .font(.bpSans(BPType.bodyS, .regular))
                    .foregroundStyle(BP.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if let extraAction {
                    Button(extraAction.0, action: extraAction.1)
                        .font(.bpSans(BPType.bodyS, .semibold))
                        .foregroundStyle(BP.brassDeep)
                        .underline()
                }
            }
        }
    }
}

/// Simple wrapping chip row for city names.
private struct FlowChips: View {
    let labels: [String]

    var body: some View {
        FlexibleChipLayout(spacing: Space.s) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.bpSans(BPType.caption, .semibold))
                    .foregroundStyle(BP.textStrong)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(BP.brass.opacity(0.7), lineWidth: 1)
                    )
            }
        }
    }
}

/// Minimal flow layout so city chips wrap naturally.
private struct FlexibleChipLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Step 3 · Permissions

@MainActor
final class BPPermissionsModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Status: Equatable {
        case unknown
        case notRequested
        case granted
        case denied

        var chip: BPChip {
            switch self {
            case .unknown: return BPChip(label: "Checking", signal: .neutral)
            case .notRequested: return BPChip(label: "Not set", signal: .neutral)
            case .granted: return BPChip(label: "On", signal: .proof)
            case .denied: return BPChip(label: "Off", signal: .caution)
            }
        }
    }

    @Published private(set) var camera: Status = .unknown
    @Published private(set) var location: Status = .unknown
    @Published private(set) var notifications: Status = .unknown

    private lazy var locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        return manager
    }()

    func refresh() {
        camera = Self.mapCamera(AVCaptureDevice.authorizationStatus(for: .video))
        location = Self.mapLocation(locationManager.authorizationStatus)
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notifications = Self.mapNotifications(settings.authorizationStatus)
        }
    }

    func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in self?.camera = granted ? .granted : .denied }
        }
    }

    func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
    }

    func requestNotifications() {
        Task {
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            notifications = granted ? .granted : .denied
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.location = Self.mapLocation(status)
        }
    }

    static func mapCamera(_ status: AVAuthorizationStatus) -> Status {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notRequested
        case .denied, .restricted: return .denied
        @unknown default: return .unknown
        }
    }

    static func mapLocation(_ status: CLAuthorizationStatus) -> Status {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        case .notDetermined: return .notRequested
        case .denied, .restricted: return .denied
        @unknown default: return .unknown
        }
    }

    static func mapNotifications(_ status: UNAuthorizationStatus) -> Status {
        switch status {
        case .authorized, .provisional, .ephemeral: return .granted
        case .notDetermined: return .notRequested
        case .denied: return .denied
        @unknown default: return .unknown
        }
    }
}

struct BPOnboardingPermissionsStep: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject var model: BPPermissionsModel
    var onContinue: () -> Void

    var body: some View {
        BPOnboardingStepScaffold(
            headline: "The instrument needs three things.",
            subhead: "Each one is asked in context and used only for capture work. You can change any of them later in Settings."
        ) {
            BPCard(padding: 0) {
                permissionRow(
                    icon: "camera.aperture",
                    title: "Camera",
                    body: "Records the walkthrough. Without it, capture can't run.",
                    status: model.camera,
                    request: model.requestCamera
                )
                BPDivider(color: BP.lineSoft)
                permissionRow(
                    icon: "location",
                    title: "Location",
                    body: "Finds assignments near you and anchors evidence to the site.",
                    status: model.location,
                    request: model.requestLocation
                )
                BPDivider(color: BP.lineSoft)
                permissionRow(
                    icon: "bell",
                    title: "Notifications",
                    body: "Assignment alerts nearby, review results, and payout updates.",
                    status: model.notifications,
                    request: model.requestNotifications
                )
            }

            BPProofBoundary(
                "Microphone & motion come later",
                message: "They're requested in context the first time you start a capture.",
                signal: .info,
                systemImage: "info.circle"
            )
        } actions: {
            BPPrimaryButton(title: "Continue", systemImage: "arrow.right") { onContinue() }
        }
        .onAppear { model.refresh() }
    }

    private func permissionRow(
        icon: String,
        title: String,
        body bodyText: String,
        status: BPPermissionsModel.Status,
        request: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(BP.textMuted)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.bpSans(BPType.body, .semibold))
                    .foregroundStyle(BP.textStrong)
                Text(bodyText)
                    .font(.bpSans(BPType.caption, .regular))
                    .foregroundStyle(BP.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s)
            switch status {
            case .notRequested, .unknown:
                Button("Allow", action: request)
                    .buttonStyle(BPOutlineChipStyle())
            case .granted:
                BPStatusChip("On", signal: .proof)
            case .denied:
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(BPOutlineChipStyle())
            }
        }
        .padding(Space.l)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Step 4 · Rights & privacy certification

struct BPOnboardingRightsStep: View {
    @State private var acknowledged = false
    var onCertified: () -> Void
    var onLater: () -> Void

    var body: some View {
        BPOnboardingStepScaffold(
            headline: "Three rules protect everyone.",
            subhead: "Certification is required before assignments treat you as rights-trained. It recertifies yearly."
        ) {
            VStack(spacing: Space.m) {
                ForEach(BPSample.principles) { principle in
                    HStack(alignment: .top, spacing: Space.m) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(BP.proofBg)
                            Text("\(principle.index)")
                                .font(.bpMono(BPType.bodyS))
                                .foregroundStyle(BP.proofFg)
                        }
                        .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(principle.title)
                                .font(.bpSans(BPType.body, .semibold))
                                .foregroundStyle(BP.textStrong)
                            Text(principle.body)
                                .font(.bpSans(BPType.caption, .regular))
                                .foregroundStyle(BP.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Space.l)
                    .bpCard()
                }
            }

            Button {
                acknowledged.toggle()
            } label: {
                HStack(alignment: .top, spacing: Space.s) {
                    Image(systemName: acknowledged ? "checkmark.square.fill" : "square")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(acknowledged ? BP.brassDeep : BP.textFaint)
                    Text("I understand and agree to capture only with permission, protect privacy, and upload truthful evidence.")
                        .font(.bpSans(BPType.caption, .regular))
                        .foregroundStyle(BP.textBody)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bpRightsAcknowledgement")
        } actions: {
            BPPrimaryButton(title: "Confirm certification", systemImage: "checkmark.shield", enabled: acknowledged) {
                onCertified()
            }
            BPGhostButton(title: "Do this later") { onLater() }
        }
    }
}

// MARK: - Step 5 · Payouts (honest, provider-gated)

struct BPOnboardingPayoutStep: View {
    /// Same availability check StripeOnboardingView uses (provider readiness
    /// AND a configured backend) — gating on the readiness flag alone would
    /// offer a setup CTA that immediately reports unavailable.
    private let payoutReady = RuntimeConfig.current.availability(for: .payouts).isEnabled
    @State private var showingPayoutSetup = false
    var onDone: () -> Void

    var body: some View {
        BPOnboardingStepScaffold(
            headline: "Accepted captures earn. Here's how the money moves.",
            subhead: "Assignment payouts are shown before you start. After review acceptance, payouts follow your payout account."
        ) {
            BPPayoutMathCard()

            if !payoutReady {
                BPProofBoundary(
                    "Payouts open soon",
                    message: "This build tracks your review history first. When payouts go live in your area, the Earnings tab unlocks account setup — approved captures record payout eligibility in the meantime.",
                    signal: .info,
                    systemImage: "clock"
                )
            }
        } actions: {
            if payoutReady {
                BPPrimaryButton(title: "Set up payouts", systemImage: "creditcard") {
                    showingPayoutSetup = true
                }
                BPGhostButton(title: "Do this later") { onDone() }
            } else {
                BPPrimaryButton(title: "Start capturing", systemImage: "camera.aperture") { onDone() }
            }
        }
        .sheet(isPresented: $showingPayoutSetup, onDismiss: onDone) {
            StripeOnboardingView()
        }
    }
}

#if DEBUG
#Preview("Onboarding flow") {
    BPOnboardingFlow()
        .environmentObject(RedesignCoordinator())
}
#endif
