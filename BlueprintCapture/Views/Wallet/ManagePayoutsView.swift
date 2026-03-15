import SwiftUI

struct ManagePayoutsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingStripe = false
    @State private var connectedMethods: Set<PayoutMethod> = []

    enum PayoutMethod: String, CaseIterable, Hashable {
        case venmo = "Venmo"
        case paypal = "PayPal"
        case crypto = "Crypto"
        case stripe = "Bank / Stripe"
    }

    private let methods: [(PayoutMethod, String, Color, String)] = [
        (.venmo,  "V",            Color(red: 0.17, green: 0.42, blue: 0.93), "v.circle.fill"),
        (.paypal, "P",            Color(red: 0.0,  green: 0.46, blue: 0.84), "p.circle.fill"),
        (.crypto, "Crypto",       Color(red: 0.44, green: 0.29, blue: 0.92), "bitcoinsign.circle.fill"),
        (.stripe, "Bank / Stripe",Color(white: 0.55),                         "building.columns.fill"),
    ]

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Header bar
                HStack {
                    Image(systemName: "b.square.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.brandTeal)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)

                // Title
                VStack(alignment: .leading, spacing: 6) {
                    Text("Manage Payouts")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                    Text("View and manage your payout settings")
                        .font(.subheadline)
                        .foregroundStyle(Color(white: 0.45))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)

                // Section label
                Text("PAYOUT METHODS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(white: 0.35))
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(connected ? "Connected" : "Not Connected")
                        .font(.caption)
                        .foregroundStyle(connected ? BlueprintTheme.successGreen : Color(white: 0.4))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(white: 0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(connected ? BlueprintTheme.successGreen.opacity(0.3) : Color(white: 0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ManagePayoutsView()
}
