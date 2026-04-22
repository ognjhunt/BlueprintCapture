import SwiftUI

struct ManagePayoutsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingStripe = false
    @State private var connectedMethods: Set<PayoutMethod> = []

    enum PayoutMethod: String, CaseIterable, Hashable {
        case stripe = "Bank / Stripe"
    }

    private let methods: [(PayoutMethod, String, Color, String)] = [
        (.stripe, "Bank / Stripe", Color(white: 0.55), "building.columns.fill"),
    ]

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Header bar
                HStack {
                    Image(systemName: "b.square.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.textPrimary)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(BlueprintTheme.body(14, weight: .semibold))
                        .foregroundStyle(BlueprintTheme.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)

                // Title
                VStack(alignment: .leading, spacing: 6) {
                    Text("Manage Payouts")
                        .font(BlueprintTheme.display(34, weight: .semibold))
                        .foregroundStyle(BlueprintTheme.textPrimary)
                    Text("View and manage your payout settings")
                        .font(BlueprintTheme.body(14, weight: .medium))
                        .foregroundStyle(BlueprintTheme.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)

                // Section label
                Text("PAYOUT METHODS")
                    .font(BlueprintTheme.body(12, weight: .bold))
                    .foregroundStyle(BlueprintTheme.textTertiary)
                    .tracking(1.2)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                // Methods list
                VStack(spacing: 10) {
                    ForEach(methods, id: \.0) { method, label, color, icon in
                        payoutMethodRow(
                            method: method,
                            label: label,
                            color: color,
                            icon: icon
                        )
                        .padding(.horizontal, 20)
                    }
                }

                Spacer()
            }
        }
        .blueprintAppBackground()
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingStripe) {
            StripeOnboardingView()
        }
    }

    private func payoutMethodRow(method: PayoutMethod, label: String, color: Color, icon: String) -> some View {
        let connected = connectedMethods.contains(method)

        return Button {
            if method == .stripe {
                showingStripe = true
            }
            // Future: connect Venmo/PayPal/Crypto flows
        } label: {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.2))
                        .frame(width: 48, height: 48)

                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(BlueprintTheme.body(14, weight: .semibold))
                        .foregroundStyle(BlueprintTheme.textPrimary)
                    Text(connected ? "Connected" : "Not Connected")
                        .font(BlueprintTheme.body(12, weight: .medium))
                        .foregroundStyle(connected ? BlueprintTheme.textPrimary : BlueprintTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .blueprintEditorialCard(radius: 18, fill: BlueprintTheme.panel)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ManagePayoutsView()
}
