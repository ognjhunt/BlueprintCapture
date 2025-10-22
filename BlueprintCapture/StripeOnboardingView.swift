import SwiftUI

struct StripeOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isLoading = false
    @State private var selectedSchedule: PayoutSchedule = .weekly
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
                                    Text("Payout schedule: \(state.payoutSchedule.displayName)")
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

                    // Payout Schedule
                    BlueprintCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundStyle(BlueprintTheme.primary)
                                Text("Payout Schedule")
                                    .font(.headline)
                                Spacer()
                            }
                            Text("Choose when Stripe pays out your earnings.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Picker("Schedule", selection: $selectedSchedule) {
                                ForEach(PayoutSchedule.allCases, id: \.self) { schedule in
                                    Text(schedule.rawValue.capitalized).tag(schedule)
                                }
                            }
                            .pickerStyle(.segmented)
                            Button(action: updateSchedule) {
                                HStack { Image(systemName: "arrow.triangle.2.circlepath"); Text("Update Schedule") }
                            }
                            .buttonStyle(BlueprintSecondaryButtonStyle())
                            Text("Default: ACH T+2 after QC passes.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    // Instant Payout
                    BlueprintCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "bolt.fill")
                                    .foregroundStyle(BlueprintTheme.warningOrange)
                                Text("Instant Cash-out")
                                    .font(.headline)
                                Spacer()
                            }
                            Text("Get funds in ~30 minutes, 24/7 (fees may apply).")
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
                self.selectedSchedule = state.payoutSchedule
            }
        } catch {
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
                await MainActor.run {
                    isLoading = false
                    _ = openURL(url)
                }
            } catch {
                await MainActor.run { isLoading = false; errorMessage = "Failed to open onboarding." }
            }
        }
    }

    private func updateSchedule() {
        isLoading = true
        Task {
            do {
                try await StripeConnectService.shared.updatePayoutSchedule(selectedSchedule)
                await loadAccountState()
                await MainActor.run { isLoading = false; showConfirmation = true }
            } catch {
                await MainActor.run { isLoading = false; errorMessage = "Failed to update schedule." }
            }
        }
    }

    private func triggerInstantPayout() {
        guard let dollars = Int(instantAmount) else { return }
        let cents = dollars * 100
        isLoading = true
        Task {
            do {
                try await StripeConnectService.shared.triggerInstantPayout(amountCents: cents)
                await loadAccountState()
                await MainActor.run { isLoading = false; showConfirmation = true; instantAmount = "" }
            } catch {
                await MainActor.run { isLoading = false; errorMessage = "Instant payout failed." }
            }
        }
    }
}

#Preview {
    StripeOnboardingView()
}


