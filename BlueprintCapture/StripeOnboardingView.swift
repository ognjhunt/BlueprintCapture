import SwiftUI

struct StripeOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isLoading = false
    @State private var instantAmount: String = ""
    @State private var showConfirmation = false
    @State private var errorMessage: String?
    @State private var accountState: StripeAccountState?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 10) {
                        Image(systemName: "banknote.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(BlueprintTheme.successGreen)
                        Text("Payouts & Onboarding")
                            .font(.title2).fontWeight(.bold)
                        Text("Manage Stripe Connect onboarding, KYC, and payouts")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)

                    if let state = accountState {
                        BlueprintCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label {
                                    Text(state.isReadyForTransfers ? "Account ready for payouts" : "Complete onboarding to enable payouts")
                                        .fontWeight(.semibold)
                                } icon: {
                                    Image(systemName: state.isReadyForTransfers ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                }
                                .foregroundStyle(state.isReadyForTransfers ? BlueprintTheme.successGreen : BlueprintTheme.warningOrange)

                                Label {
                                    Text("Payout cadence: Weekly (Mon–Sun, paid Wed–Thu)")
                                } icon: {
                                    Image(systemName: "calendar")
                                }
                                .foregroundStyle(.secondary)

                                if let next = state.nextPayout {
                                    Label {
                                        Text("Next payout \(next.estimatedArrival.formatted(.dateTime.month(.abbreviated).day().year())) · \(next.amount, format: .currency(code: "USD"))")
                                    } icon: {
                                        Image(systemName: "calendar.badge.clock")
                                    }
                                    .foregroundStyle(.secondary)
                                }

                                if let requirements = state.requirementsDue, !requirements.isEmpty {
                                    Text("Pending: \(requirements.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundStyle(BlueprintTheme.warningOrange)
                                }
                            }
                        }
                    }

                    // KYC & Onboarding
                    BlueprintCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .foregroundStyle(BlueprintTheme.primary)
                                Text("Complete KYC")
                                    .font(.headline)
                                Spacer()
                            }
                            Text("Open Stripe's Express onboarding to verify your identity and enable payouts.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button(action: openStripeOnboarding) {
                                HStack { Image(systemName: "link"); Text("Open Stripe Onboarding") }
                            }
                            .buttonStyle(BlueprintPrimaryButtonStyle())
                            .disabled(isLoading)
                            Text("Includes 1099 e-delivery when you scale.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    // Payout Options (Uber/DoorDash style)
                    BlueprintCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundStyle(BlueprintTheme.primary)
                                Text("Payout Options")
                                    .font(.headline)
                                Spacer()
                            }
                            Text("We follow the same approach as Uber/DoorDash.")
                                .font(.subheadline).foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    Image(systemName: "calendar").foregroundStyle(BlueprintTheme.primary)
                                    Text("Default: Weekly (Mon–Sun earnings paid Wed–Thu)")
                                        .font(.subheadline)
                                        .blueprintPrimaryOnDark()
                                }
                                HStack(spacing: 12) {
                                    Image(systemName: "creditcard.fill").foregroundStyle(BlueprintTheme.accentAqua)
                                    Text("After each capture: Auto-deposit to Blueprint Card (no fee)")
                                        .font(.subheadline)
                                        .blueprintPrimaryOnDark()
                                }
                                HStack(spacing: 12) {
                                    Image(systemName: "bolt.fill").foregroundStyle(BlueprintTheme.warningOrange)
                                    Text("Instant Pay: Same-day cash out to your debit (fee applies)")
                                        .font(.subheadline)
                                        .blueprintPrimaryOnDark()
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.10))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                        }
                    }

                    // Instant Payout
                    BlueprintCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "bolt.fill")
                                    .foregroundStyle(BlueprintTheme.warningOrange)
                                Text("Instant Pay")
                                    .font(.headline)
                                Spacer()
                            }
                            Text("Same-day cash out to your debit. Usually minutes; bank timing may vary.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            HStack {
                                TextField("Amount (USD)", text: $instantAmount)
                                    .keyboardType(.numberPad)
                                Text("USD").foregroundStyle(.secondary)
                            }
                            Button(action: triggerInstantPayout) {
                                HStack { Image(systemName: "paperplane.fill"); Text("Cash Out Now") }
                            }
                            .buttonStyle(BlueprintPrimaryButtonStyle())
                            .disabled(
                                isLoading ||
                                Int(instantAmount) == nil ||
                                !(accountState?.instantPayoutEligible ?? false)
                            )

                            if accountState?.instantPayoutEligible == true {
                                Text("Uses Stripe Instant Payouts to debit card or bank when eligible.")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Instant cash-out unlocks once Stripe approves your account and you have an eligible balance.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Stripe Payouts")
            .navigationBarTitleDisplayMode(.inline)
            .blueprintScreenBackground()
            .overlay {
                if isLoading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.opacity(0.1)) }
            }
            .alert("Done", isPresented: $showConfirmation) { Button("OK") { showConfirmation = false } } message: { Text("Action completed successfully.") }
            .alert("Error", isPresented: .constant(errorMessage != nil)) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
            .task {
                isLoading = true
                await loadAccountState()
                isLoading = false
            }
        }
    }

    private func loadAccountState() async {
        do {
            let state = try await StripeConnectService.shared.fetchAccountState()
            await MainActor.run {
                self.accountState = state
            }
        } catch {
            print("[StripeUI] ✗ Error loading account state: \(error)")
            await MainActor.run {
                if self.accountState == nil {
                    self.errorMessage = "Unable to load Stripe account status."
                }
            }
        }
    }

    private func openStripeOnboarding() {
        isLoading = true
        Task {
            do {
                let url = try await StripeConnectService.shared.createOnboardingLink()
                print("[StripeUI] ✓ Onboarding link obtained: \(url.absoluteString)")
                await MainActor.run {
                    isLoading = false
                    _ = openURL(url)
                }
            } catch {
                print("[StripeUI] ✗ Error creating onboarding link: \(error)")
                await MainActor.run { isLoading = false; errorMessage = "Failed to open onboarding." }
            }
        }
    }

    // removed schedule update per Uber/DoorDash payout model

    private func triggerInstantPayout() {
        guard let dollars = Int(instantAmount) else { return }
        let cents = dollars * 100
        isLoading = true
        Task {
            do {
                try await StripeConnectService.shared.triggerInstantPayout(amountCents: cents)
                print("[StripeUI] ✓ Instant payout triggered successfully")
                await loadAccountState()
                await MainActor.run { isLoading = false; showConfirmation = true; instantAmount = "" }
            } catch {
                print("[StripeUI] ✗ Error triggering instant payout: \(error)")
                await MainActor.run { isLoading = false; errorMessage = "Instant payout failed." }
            }
        }
    }
}

#Preview {
    StripeOnboardingView()
}


