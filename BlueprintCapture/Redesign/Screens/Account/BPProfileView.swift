import SwiftUI
import FirebaseAuth
import Combine
import ARKit
import UIKit

enum BPAccountRoute: Hashable { case settings, rights, support, howItWorks }

// MARK: - Profile stats (real)
//
// Captures / earned / pass-rate come from the creator backend when configured.
// When the backend is unreachable the tiles render "—" instead of fabricated
// numbers (AGENTS.md: never fabricate readiness or performance).

@MainActor
final class BPProfileViewModel: ObservableObject {
    struct Stats: Equatable {
        var capturesCompleted: Int?
        var totalEarned: Decimal?
        var passRate: Double?
    }

    @Published private(set) var stats = Stats()
    @Published private(set) var isLoading = false

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var next = Stats()
        if let earnings = try? await APIService.shared.fetchEarnings() {
            next.capturesCompleted = earnings.scansCompleted
            next.totalEarned = earnings.total
        }
        if let qc = try? await APIService.shared.fetchQualityControlStatus(),
           qc.pendingCount + qc.needsFixCount + qc.approvedCount > 0 {
            next.passRate = qc.approvalRate
        }
        stats = next
    }
}

// MARK: - Profile (tab: Profile)
//
// Identity comes from the authenticated Firebase user via RedesignCoordinator.
// No sample personas, fabricated stats, or unearned certification chips —
// capture-truth rules forbid presenting qualification/performance data that
// the backend has not actually produced.

struct BPProfileView: View {
    @EnvironmentObject private var coordinator: RedesignCoordinator
    @StateObject private var viewModel = BPProfileViewModel()
    @ObservedObject private var capturerState = BPCapturerStateStore.shared
    @State private var confirmingSignOut = false
    @State private var isSigningOut = false
    @State private var signOutErrorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    BPLargeTitle(eyebrow: eyebrow, title: "Profile")
                    identityCard
                    statRow
                    menuCard
                    BPGhostButton(
                        title: isSigningOut ? "Signing out…" : "Sign out",
                        tint: BP.blockFg,
                        border: BP.blockBd
                    ) { confirmingSignOut = true }
                        .disabled(isSigningOut)
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.s)
                .padding(.bottom, Space.l)
            }
            .scrollIndicators(.hidden)
            .background(BP.canvas.ignoresSafeArea())
            .navigationBarHidden(true)
            .bpTabBarOverlay(selection: $coordinator.selectedTab, onCapture: { coordinator.startCapture() })
            .navigationDestination(for: BPAccountRoute.self) { route in
                switch route {
                case .settings: BPSettingsView()
                case .rights: BPRightsTrainingView()
                case .support: BPSupportHelpView()
                case .howItWorks: BPHowItWorksView()
                }
            }
            .task { await viewModel.load() }
            .confirmationDialog(
                "Sign out of Blueprint Capture?",
                isPresented: $confirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) { signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Queued uploads stay on this device and resume after you sign back in.")
            }
            .alert(
                "Sign out failed",
                isPresented: Binding(
                    get: { signOutErrorMessage != nil },
                    set: { if !$0 { signOutErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { signOutErrorMessage = nil }
            } message: {
                Text(signOutErrorMessage ?? "")
            }
        }
    }

    private var eyebrow: String {
        coordinator.capturerReference.isEmpty ? "Capturer" : coordinator.capturerReference
    }

    private var identityCard: some View {
        BPCard {
            HStack(spacing: Space.l) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(BP.infoBg)
                    Text(initials)
                        .font(.bpSans(BPType.title, .bold))
                        .foregroundStyle(BP.infoFg)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(displayName)
                        .font(.bpSans(BPType.bodyL, .semibold))
                        .foregroundStyle(BP.textStrong)
                    Text(identitySubtitle)
                        .font(.bpMono(BPType.caption))
                        .foregroundStyle(BP.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.s)
            }
        }
    }

    private var displayName: String {
        coordinator.capturerName.isEmpty ? "Capturer" : coordinator.capturerName
    }

    private var identitySubtitle: String {
        var parts: [String] = []
        if !coordinator.capturerEmail.isEmpty { parts.append(coordinator.capturerEmail) }
        if !coordinator.capturerCity.isEmpty { parts.append(coordinator.capturerCity) }
        return parts.isEmpty ? "Signed in" : parts.joined(separator: "  ·  ")
    }

    private var initials: String {
        let source = displayName
        let parts = source.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        let value = String(letters).uppercased()
        return value.isEmpty ? "C" : value
    }

    private var statRow: some View {
        HStack(spacing: Space.m) {
            BPMetricStat(value: viewModel.stats.capturesCompleted.map(String.init) ?? "—", label: "Captures")
            BPMetricStat(value: earnedLabel, label: "Earned")
            BPMetricStat(
                value: passRateLabel,
                label: "Pass rate",
                valueColor: viewModel.stats.passRate != nil ? BP.proofFg : BP.textStrong
            )
        }
    }

    private var earnedLabel: String {
        guard let total = viewModel.stats.totalEarned else { return "—" }
        return BPFormat.currency(NSDecimalNumber(decimal: total).doubleValue, fractionDigits: 0)
    }

    private var passRateLabel: String {
        guard let rate = viewModel.stats.passRate else { return "—" }
        return "\(Int((rate * 100).rounded()))%"
    }

    private var menuCard: some View {
        BPCard(padding: 0) {
            NavigationLink(value: BPAccountRoute.rights) {
                menuRow(icon: "checkmark.shield", title: "Rights & privacy",
                        trailingChip: capturerState.isRightsCertified
                            ? BPChip(label: "Certified", signal: .proof)
                            : BPChip(label: "Required", signal: .caution))
            }
            .buttonStyle(.plain)
            BPDivider(color: BP.lineSoft)

            menuRow(icon: "iphone", title: "Capture device", trailingText: Self.deviceLabel, showsChevron: false)
            BPDivider(color: BP.lineSoft)

            NavigationLink(value: BPAccountRoute.howItWorks) {
                menuRow(icon: "book", title: "How Blueprint works")
            }
            .buttonStyle(.plain)
            BPDivider(color: BP.lineSoft)

            NavigationLink(value: BPAccountRoute.settings) {
                menuRow(icon: "gearshape", title: "Settings")
            }
            .buttonStyle(.plain)
            BPDivider(color: BP.lineSoft)

            NavigationLink(value: BPAccountRoute.support) {
                menuRow(icon: "questionmark.circle", title: "Help", trailingText: "Beta guide")
            }
            .buttonStyle(.plain)
        }
    }

    /// Truthful device descriptor — device class + real LiDAR capability.
    static var deviceLabel: String {
        let model = UIDevice.current.model
        let lidar = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        return lidar ? "\(model) · LiDAR" : model
    }

    private func signOut() {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        do {
            try Auth.auth().signOut()
            UserDeviceService.ensureAnonymousFirebaseUserIfNeeded()
            NotificationCenter.default.post(name: .AuthStateDidChange, object: nil)
            coordinator.applyLocalIdentity()
        } catch {
            signOutErrorMessage = error.localizedDescription
        }
    }

    private func menuRow(
        icon: String,
        title: String,
        trailingText: String? = nil,
        trailingChip: BPChip? = nil,
        showsChevron: Bool = true
    ) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(BP.textMuted)
                .frame(width: 24)
            Text(title)
                .font(.bpSans(BPType.body, .semibold))
                .foregroundStyle(BP.textStrong)
            Spacer(minLength: Space.s)
            if let trailingChip {
                BPStatusChip(trailingChip.label, signal: trailingChip.signal)
            }
            if let trailingText {
                Text(trailingText)
                    .font(.bpMono(BPType.caption))
                    .foregroundStyle(BP.textMuted)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BP.textFaint)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .contentShape(Rectangle())
    }
}

private struct BPSupportHelpView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            BPNavBar("Support")
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    group("Start here") {
                        actionRow("Email support", AppConfig.effectiveSupportEmailAddress(), systemImage: "envelope") {
                            if let url = AppConfig.supportEmailURL(subject: "Blueprint Capture Support") {
                                openURL(url)
                            }
                        }
                        BPDivider(color: BP.lineSoft)
                        actionRow("Beta capturer guide", "Scope, first run, review states, payout expectations, and escalation.", systemImage: "list.bullet.rectangle") {
                            openURL(AppConfig.betaCapturerGuideURL())
                        }
                        BPDivider(color: BP.lineSoft)
                        actionRow("Report a bug", "Falls back to support email if bug reporting is not configured.", systemImage: "ant") {
                            openURL(AppConfig.bugReportOrSupportURL())
                        }
                    }

                    group("Escalate when") {
                        guidanceRow("Upload is stalled for more than 24 hours")
                        BPDivider(color: BP.lineSoft)
                        guidanceRow("Private or restricted content was captured")
                        BPDivider(color: BP.lineSoft)
                        guidanceRow("Payout, account, blocked, or degraded status is unclear")
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.l)
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
        }
        .background(BP.canvas.ignoresSafeArea())
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            BPEyebrow(title)
            BPCard(padding: 0) { content() }
        }
    }

    private func actionRow(
        _ title: String,
        _ subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(BP.textMuted)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.bpSans(BPType.body, .semibold))
                        .foregroundStyle(BP.textStrong)
                    Text(subtitle)
                        .font(.bpSans(BPType.caption, .regular))
                        .foregroundStyle(BP.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Space.m)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BP.textFaint)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func guidanceRow(_ text: String) -> some View {
        Text(text)
            .font(.bpSans(BPType.body, .semibold))
            .foregroundStyle(BP.textStrong)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
    }
}

#if DEBUG
#Preview {
    BPProfileView().environmentObject(RedesignCoordinator())
}
#endif
