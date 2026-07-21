import SwiftUI

// MARK: - Earnings & payouts (tab: Earnings)
//
// Fully real wallet: earnings totals, payout ledger, and Stripe verification
// state come from `BPEarningsViewModel` (backend-derived). CAP-11: payout
// onboarding is gated on real provider readiness (BLUEPRINT_PAYOUT_PROVIDER_READY)
// — when the flag is NO the honest "unavailable" panel shows and no cashout UI
// is reachable. No sample data on this screen.

struct BPEarningsView: View {
    @EnvironmentObject private var coordinator: RedesignCoordinator
    @StateObject private var viewModel = BPEarningsViewModel()
    @State private var showingPayoutSetup = false
    @State private var showingPayoutMath = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                BPLargeTitle(eyebrow: "Wallet", title: "Earnings") {
                    BPTextAction(title: "How payouts work") { showingPayoutMath = true }
                }

                if case .failed(let message) = viewModel.phase {
                    syncBanner(message)
                }

                balancePanel
                statRow
                lifecycleStrip
                payoutsSection
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.s)
            .padding(.bottom, Space.l)
        }
        .scrollIndicators(.hidden)
        .background(BP.canvas.ignoresSafeArea())
        .bpTabBarOverlay(selection: $coordinator.selectedTab, onCapture: { coordinator.startCapture() })
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $showingPayoutSetup, onDismiss: { Task { await viewModel.load() } }) {
            StripeOnboardingView()
        }
        .sheet(isPresented: $showingPayoutMath) {
            BPPayoutMathSheet()
        }
    }

    // MARK: Sync failure (honest, retryable)

    private func syncBanner(_ message: String) -> some View {
        BPProofBoundary(
            "Sync unavailable",
            message: "\(message) Pull to refresh to try again.",
            signal: .caution,
            systemImage: "arrow.clockwise"
        )
    }

    // MARK: Balance panel (dark, evidence-grid)

    @ViewBuilder
    private var balancePanel: some View {
        if viewModel.payoutReady {
            livePayoutPanel
        } else {
            reviewTrackingPanel
        }
    }

    /// Provider live: real balance + verification-aware CTA.
    private var livePayoutPanel: some View {
        BPDarkPanel {
            HStack(alignment: .firstTextBaseline) {
                Text("Payouts")
                    .bpEyebrow(BP.onInk.opacity(0.6))
                Spacer()
                if let verification = viewModel.verification {
                    verificationChip(verification)
                }
            }
            Text(viewModel.totalEarnedLabel)
                .font(.bpMono(34))
                .foregroundStyle(BP.onInk)
                .padding(.top, Space.xs)
            Text(pendingLine)
                .font(.bpMono(BPType.caption))
                .foregroundStyle(BP.onInk.opacity(0.6))

            if let next = viewModel.accountState?.nextPayout {
                Text("Next payout \(next.estimatedArrival.formatted(.dateTime.month(.abbreviated).day())) · \(BPFormat.currency(Double(next.amountCents) / 100.0))")
                    .font(.bpMono(BPType.caption))
                    .foregroundStyle(BP.onInk.opacity(0.75))
                    .padding(.top, Space.xs)
            }

            BPPrimaryButton(
                title: payoutCTATitle,
                systemImage: "creditcard"
            ) {
                showingPayoutSetup = true
            }
            .padding(.top, Space.m)
        }
    }

    private var payoutCTATitle: String {
        guard let verification = viewModel.verification else { return "Set up payouts" }
        switch verification.overallStatus {
        case .verified: return "Manage payouts"
        case .actionRequired: return "Finish verification"
        case .pendingReview: return "View verification"
        case .notStarted: return "Set up payouts"
        case .unavailable: return "Payout status"
        }
    }

    private func verificationChip(_ verification: PayoutVerificationSummary) -> some View {
        let (label, signal): (String, BPSignal) = {
            switch verification.overallStatus {
            case .verified: return ("Verified", .proof)
            case .pendingReview: return ("In review", .info)
            case .actionRequired: return ("Action needed", .caution)
            case .notStarted: return ("Not set up", .neutral)
            case .unavailable: return ("Unavailable", .neutral)
            }
        }()
        return BPStatusChip(label, signal: signal)
    }

    /// Provider not live: track earned-to-date honestly, no cashout affordance.
    private var reviewTrackingPanel: some View {
        BPDarkPanel {
            Text("Earned to date")
                .bpEyebrow(BP.onInk.opacity(0.6))
            Text(viewModel.totalEarnedLabel)
                .font(.bpMono(34))
                .foregroundStyle(BP.onInk)
                .padding(.top, Space.xs)
            Text(pendingLine)
                .font(.bpMono(BPType.caption))
                .foregroundStyle(BP.onInk.opacity(0.6))
            Text("Payout onboarding and cashout unlock when provider readiness is enabled for your cohort. Accepted captures record payout eligibility in the meantime.")
                .font(.bpSans(BPType.caption, .regular))
                .foregroundStyle(BP.onInk.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.m)
        }
    }

    private var pendingLine: String {
        viewModel.pending != nil ? "\(viewModel.pendingLabel) pending review" : "Pending review syncs with the backend"
    }

    // MARK: Stats (real)

    private var statRow: some View {
        HStack(spacing: Space.m) {
            BPMetricStat(value: viewModel.capturesCompleted.map(String.init) ?? "—", label: "Captures")
            BPMetricStat(value: viewModel.pendingLabel, label: "Pending")
        }
    }

    // MARK: Lifecycle strip (comprehension)

    private var lifecycleStrip: some View {
        BPCard(padding: Space.m) {
            HStack(spacing: 0) {
                lifecycleStep(index: 1, label: "Capture")
                lifecycleArrow
                lifecycleStep(index: 2, label: "Review")
                lifecycleArrow
                lifecycleStep(index: 3, label: "Accepted")
                lifecycleArrow
                lifecycleStep(index: 4, label: "Paid")
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Payout lifecycle: capture, then review, then accepted, then paid")
    }

    private func lifecycleStep(index: Int, label: String) -> some View {
        VStack(spacing: Space.xs) {
            Text("0\(index)")
                .font(.bpMono(BPType.caption))
                .foregroundStyle(BP.brassDeep)
            Text(label)
                .font(.bpSans(BPType.caption, .semibold))
                .foregroundStyle(BP.textStrong)
        }
        .frame(maxWidth: .infinity)
    }

    private var lifecycleArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(BP.textFaint)
    }

    // MARK: Payout ledger (real)

    private var payoutsSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Payouts")
                    .font(.bpSans(BPType.title, .semibold))
                    .tracking(BPTracking.headline)
                    .foregroundStyle(BP.textStrong)
                Spacer()
                Button {
                    coordinator.selectedTab = .history
                } label: {
                    Text("Capture history")
                        .font(.bpSans(BPType.bodyS, .semibold))
                        .foregroundStyle(BP.brassDeep)
                }
            }

            if viewModel.phase == .loading && viewModel.ledger.isEmpty {
                loadingCard
            } else if viewModel.ledger.isEmpty {
                emptyLedgerCard
            } else {
                BPCard(padding: Space.s) {
                    ForEach(Array(viewModel.ledger.prefix(12).enumerated()), id: \.element.id) { idx, entry in
                        payoutRow(entry)
                        if idx < min(viewModel.ledger.count, 12) - 1 { BPDivider(color: BP.lineSoft) }
                    }
                }
            }
        }
    }

    private func payoutRow(_ entry: PayoutLedgerEntry) -> some View {
        let status = BPStatusPresentation.entry(for: entry.status)
        return HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.description ?? "Capture payout")
                    .font(.bpSans(BPType.body, .semibold))
                    .foregroundStyle(BP.textStrong)
                    .lineLimit(1)
                Text(entry.scheduledFor.formatted(date: .abbreviated, time: .omitted))
                    .font(.bpMono(BPType.caption))
                    .foregroundStyle(BP.textMuted)
            }
            Spacer(minLength: Space.s)
            VStack(alignment: .trailing, spacing: 3) {
                Text(BPFormat.currency(NSDecimalNumber(decimal: entry.amount).doubleValue))
                    .font(.bpMono(BPType.body))
                    .foregroundStyle(BP.textStrong)
                BPStatusChip(status.label, signal: status.signal)
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.m)
        .accessibilityElement(children: .combine)
    }

    private var loadingCard: some View {
        BPCard {
            HStack(spacing: Space.m) {
                ProgressView().controlSize(.small)
                Text("Syncing payout ledger…")
                    .font(.bpSans(BPType.bodyS, .regular))
                    .foregroundStyle(BP.textMuted)
            }
        }
    }

    private var emptyLedgerCard: some View {
        BPCard {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("No payouts yet")
                    .font(.bpSans(BPType.body, .semibold))
                    .foregroundStyle(BP.textStrong)
                Text("Payouts appear here after captures are accepted in review. Payout eligibility always follows review — check History for where each capture stands.")
                    .font(.bpSans(BPType.caption, .regular))
                    .foregroundStyle(BP.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Payout math sheet

struct BPPayoutMathSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            BPNavBar(title: "How payouts work", showsBack: false) {
                BPTextAction(title: "Done") { dismiss() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    BPPayoutMathCard()
                }
                .padding(.horizontal, Space.l)
                .padding(.top, Space.l)
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
        }
        .background(BP.canvas.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}

#if DEBUG
#Preview { BPEarningsView().environmentObject(RedesignCoordinator()) }
#endif
