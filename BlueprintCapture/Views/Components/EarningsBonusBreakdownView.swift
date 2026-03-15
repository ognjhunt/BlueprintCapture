import SwiftUI

struct EarningsBonusBreakdownView: View {
    struct BonusRow: Identifiable {
        let label: String
        let amount: Double
        let highlight: Bool

        var id: String { label }
    }

    let basePayoutCents: Int
    let deviceMultiplier: Double
    let bonusRows: [BonusRow]
    let totalAmount: Double

    init(
        basePayoutCents: Int,
        deviceMultiplier: Double,
        coverageBonus: Double,
        multiPassBonus: Double,
        lidarBonus: Double,
        steadinessBonus: Double
    ) {
        self.basePayoutCents = basePayoutCents
        self.deviceMultiplier = deviceMultiplier

        let baseDollars = Double(basePayoutCents) / 100.0
        var rows: [BonusRow] = []
        if coverageBonus > 0 {
            rows.append(BonusRow(label: "Coverage bonus (+\(Int(coverageBonus * 100))%)", amount: baseDollars * coverageBonus, highlight: true))
        }
        if multiPassBonus > 0 {
            rows.append(BonusRow(label: "Multi-pass bonus (+\(Int(multiPassBonus * 100))%)", amount: baseDollars * multiPassBonus, highlight: true))
        }
        if lidarBonus > 0 {
            rows.append(BonusRow(label: "LiDAR depth bonus (+\(Int(lidarBonus * 100))%)", amount: baseDollars * lidarBonus, highlight: true))
        }
        if steadinessBonus > 0 {
            rows.append(BonusRow(label: "Steady walkthrough (+\(Int(steadinessBonus * 100))%)", amount: baseDollars * steadinessBonus, highlight: true))
        }
        self.bonusRows = rows
        let bonusMultiplier = 1.0 + coverageBonus + multiPassBonus + lidarBonus + steadinessBonus
        self.totalAmount = baseDollars * bonusMultiplier * deviceMultiplier
    }

    init(
        basePayoutCents: Int,
        deviceMultiplier: Double,
        bonuses: [CaptureEarningsBonus],
        totalPayoutCents: Int?
    ) {
        self.basePayoutCents = basePayoutCents
        self.deviceMultiplier = deviceMultiplier
        self.bonusRows = bonuses.map {
            BonusRow(
                label: $0.label,
                amount: Double($0.amountCents ?? 0) / 100.0,
                highlight: true
            )
        }
        self.totalAmount = Double(totalPayoutCents ?? basePayoutCents) / 100.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Earnings Breakdown", systemImage: "chart.bar.fill")
                .font(.headline)

            bonusRow(label: "Base payout", amount: baseDollars, highlight: false)

            ForEach(bonusRows) { row in
                bonusRow(label: row.label, amount: row.amount, highlight: row.highlight)
            }

            if deviceMultiplier > 1.0 {
                HStack {
                    Text("Device multiplier")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(deviceMultiplier))x")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.brandTeal)
                }
            }

            Divider()

            HStack {
                Text("Total")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(totalAmount, format: .currency(code: "USD"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(BlueprintTheme.successGreen)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var baseDollars: Double {
        Double(basePayoutCents) / 100.0
    }

    private func bonusRow(label: String, amount: Double, highlight: Bool) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(highlight ? .primary : .secondary)
            Spacer()
            Text(amount, format: .currency(code: "USD"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(highlight ? BlueprintTheme.successGreen : .secondary)
        }
    }
}

#Preview {
    EarningsBonusBreakdownView(
        basePayoutCents: 3500,
        deviceMultiplier: 4.0,
        coverageBonus: 0.25,
        multiPassBonus: 0.0,
        lidarBonus: 1.0,
        steadinessBonus: 0.20
    )
    .padding()
    .preferredColorScheme(.dark)
}
