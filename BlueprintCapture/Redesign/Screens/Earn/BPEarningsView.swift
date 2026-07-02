import SwiftUI

// MARK: - Wallet status (tab: Earnings)

struct BPEarningsView: View {
    @EnvironmentObject private var coordinator: RedesignCoordinator
    private let history = BPSample.history

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                BPLargeTitle(eyebrow: "Wallet", title: "Review status")
                providerUnavailableCard
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
            BPMetricStat(value: "3", label: "Reviewed")
            BPMetricStat(value: "1", label: "Needs fix")
        }
    }

    private var reviewHistorySection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Recent reviews")
                .font(.bpSans(BPType.title, .semibold))
                .tracking(BPTracking.headline)
                .foregroundStyle(BP.textStrong)
            BPCard(padding: Space.s) {
                ForEach(Array(history.enumerated()), id: \.element.id) { idx, item in
                    HStack(spacing: Space.m) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.site)
                                .font(.bpSans(BPType.body, .semibold))
                                .foregroundStyle(BP.textStrong)
                                .lineLimit(1)
                            Text(item.meta)
                                .font(.bpMono(BPType.caption))
                                .foregroundStyle(BP.textMuted)
                        }
                        Spacer(minLength: Space.s)
                        BPStatusChip(item.status.label, signal: item.status.signal)
                    }
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.m)
                    if idx < history.count - 1 { BPDivider(color: BP.lineSoft) }
                }
            }
        }
    }
}

#if DEBUG
#Preview { BPEarningsView().environmentObject(RedesignCoordinator()) }
#endif
