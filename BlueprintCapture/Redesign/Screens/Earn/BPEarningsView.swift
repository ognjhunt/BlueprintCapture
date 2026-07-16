import SwiftUI

// MARK: - Wallet status (tab: Earnings)

struct BPEarningsView: View {
    @EnvironmentObject private var coordinator: RedesignCoordinator
    @StateObject private var store = BPCaptureHistoryStore()
    // CAP-11: payout onboarding is reachable from the shipping UI, gated on real
    // backend provider readiness (BLUEPRINT_PAYOUT_PROVIDER_READY). When the flag is
    // NO the honest "unavailable" card shows; when the backend flips it to YES the
    // real Stripe Connect onboarding (StripeOnboardingView) is presented.
    private let payoutReady = RuntimeConfig.current.payoutProviderReady
    @State private var showingPayoutSetup = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                BPLargeTitle(eyebrow: "Wallet", title: "Review status")
                if payoutReady {
                    payoutSetupCard
                } else {
                    providerUnavailableCard
                }
                statRow
                reviewHistorySection
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.s)
            .padding(.bottom, Space.l)
        }
        .scrollIndicators(.hidden)
        .background(BP.canvas.ignoresSafeArea())
        .bpTabBarOverlay(selection: $coordinator.selectedTab, onCapture: { coordinator.startCapture() })
        .sheet(isPresented: $showingPayoutSetup) {
            StripeOnboardingView()
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    private var payoutSetupCard: some View {
        BPDarkPanel {
            Text("Payouts")
                .bpEyebrow(BP.onInk.opacity(0.6))
            Text("Set up cashout")
                .font(.bpDisplay(30))
                .foregroundStyle(BP.onInk)
            Text("Connect your payout account to receive earnings after captures pass review.")
                .font(.bpSans(BPType.caption, .regular))
                .foregroundStyle(BP.onInk.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.xs)
            BPPrimaryButton(title: "Set up payouts", systemImage: "creditcard") {
                showingPayoutSetup = true
            }
            .padding(.top, Space.m)
        }
    }

    private var providerUnavailableCard: some View {
        BPDarkPanel {
            Text("Payout setup unavailable")
                .bpEyebrow(BP.onInk.opacity(0.6))
            Text("No live balance")
                .font(.bpDisplay(30))
                .foregroundStyle(BP.onInk)
            Text("This build tracks capture review history. Payout onboarding and cashout stay hidden until backend provider readiness is enabled for the cohort.")
                .font(.bpSans(BPType.caption, .regular))
                .foregroundStyle(BP.onInk.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.xs)
        }
    }

    private var statRow: some View {
        HStack(spacing: Space.m) {
            BPMetricStat(value: "\(store.reviewedCount)", label: "Reviewed")
            BPMetricStat(value: "\(store.needsFixCount)", label: "Needs fix")
        }
    }

    /// Reviewed captures only — a capture appears here once the backend has
    /// actually produced a verdict (approved / paid / rejected / needs fix).
    private var reviewedEntries: [BPCaptureHistoryEntry] {
        store.entries.filter(\.isReviewed)
    }

    private var reviewHistorySection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Recent reviews")
                .font(.bpSans(BPType.title, .semibold))
                .tracking(BPTracking.headline)
                .foregroundStyle(BP.textStrong)
            if reviewedEntries.isEmpty {
                VStack(spacing: Space.s) {
                    Text("No reviews yet")
                        .font(.bpSans(BPType.body, .semibold))
                        .foregroundStyle(BP.textStrong)
                    Text("Captures appear here after the review team issues a verdict.")
                        .font(.bpSans(BPType.caption, .regular))
                        .foregroundStyle(BP.textMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(Space.xl)
                .bpCard()
            } else {
                BPCard(padding: Space.s) {
                    ForEach(Array(reviewedEntries.prefix(10).enumerated()), id: \.element.id) { idx, entry in
                        HStack(spacing: Space.m) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.site)
                                    .font(.bpSans(BPType.body, .semibold))
                                    .foregroundStyle(BP.textStrong)
                                    .lineLimit(1)
                                if !entry.meta.isEmpty {
                                    Text(entry.meta)
                                        .font(.bpMono(BPType.caption))
                                        .foregroundStyle(BP.textMuted)
                                }
                            }
                            Spacer(minLength: Space.s)
                            BPStatusChip(entry.chip.label, signal: entry.chip.signal)
                        }
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, Space.m)
                        if idx < min(reviewedEntries.count, 10) - 1 { BPDivider(color: BP.lineSoft) }
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview { BPEarningsView().environmentObject(RedesignCoordinator()) }
#endif
