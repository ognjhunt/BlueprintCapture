import SwiftUI

// MARK: - Earnings & payouts (tab: Earnings)

struct BPEarningsView: View {
    @EnvironmentObject private var coordinator: RedesignCoordinator
    private let payouts = BPSample.payouts

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                BPLargeTitle(eyebrow: "Wallet", title: "Earnings")
                balanceCard
                statRow
                payoutsSection
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.s)
            .padding(.bottom, Space.l)
        }
        .scrollIndicators(.hidden)
        .background(BP.canvas.ignoresSafeArea())
        .bpTabBarOverlay(selection: $coordinator.selectedTab, onCapture: { coordinator.startCapture() })
    }

    private var balanceCard: some View {
        BPDarkPanel {
            Text("Available balance")
                .bpEyebrow(BP.onInk.opacity(0.6))
            Text(BPFormat.currency(312.00))
                .font(.bpMono(40))
                .foregroundStyle(BP.onInk)
            Button(action: {}) {
                Text("Cash out")
            }
            .buttonStyle(BPPrimaryButtonStyle())
            .padding(.top, Space.xs)
        }
    }

    private var statRow: some View {
        HStack(spacing: Space.m) {
            BPMetricStat(value: BPFormat.currency(1240, fractionDigits: 0), label: "This month")
            BPMetricStat(value: "27", label: "Captures")
        }
    }

    private var payoutsSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Recent payouts")
                .font(.bpSans(BPType.title, .semibold))
                .tracking(BPTracking.headline)
                .foregroundStyle(BP.textStrong)
            BPCard(padding: Space.s) {
                ForEach(Array(payouts.enumerated()), id: \.element.id) { idx, payout in
                    HStack(spacing: Space.m) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(payout.site)
                                .font(.bpSans(BPType.body, .semibold))
                                .foregroundStyle(BP.textStrong)
                                .lineLimit(1)
                            Text(payout.date)
                                .font(.bpMono(BPType.caption))
                                .foregroundStyle(BP.textMuted)
                        }
                        Spacer(minLength: Space.s)
                        VStack(alignment: .trailing, spacing: Space.s) {
                            Text(BPFormat.currency(payout.amount))
                                .font(.bpMono(BPType.body))
                                .foregroundStyle(BP.textStrong)
                            BPStatusChip(payout.status.label, signal: payout.status.signal)
                        }
                    }
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.m)
                    if idx < payouts.count - 1 { BPDivider(color: BP.lineSoft) }
                }
            }
        }
    }
}

#if DEBUG
#Preview { BPEarningsView().environmentObject(RedesignCoordinator()) }
#endif
