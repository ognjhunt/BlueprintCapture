import SwiftUI

struct StripeBillingSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SettingsViewModel
    
    @State private var showPlaidSimulation = false
    @State private var simulatedBankName = ""
    @State private var simulatedLastFour = ""
    @State private var isConnectingPlaid = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "building.columns.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [BlueprintTheme.primary, BlueprintTheme.accentAqua],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("Connect Your Bank Account")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Securely connect your bank account to receive payouts for completed scans")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 32)
                    
                    // Features
                    VStack(spacing: 16) {
                        FeatureRow(
                            icon: "lock.shield.fill",
                            title: "Bank-level Security",
                            description: "Your data is encrypted and secure via Plaid"
                        )
                        
                        FeatureRow(
                            icon: "bolt.fill",
                            title: "Fast Payouts",
                            description: "Receive payments within 2 business days"
                        )
                        
                        FeatureRow(
                            icon: "checkmark.seal.fill",
                            title: "Powered by Stripe + Plaid",
                            description: "Trusted by millions of users worldwide"
                        )
                    }
                    .padding(.horizontal)
                    
                    // Info Box
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(BlueprintTheme.accentAqua)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Plaid Integration")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(BlueprintTheme.accentAqua)
                            
                            Text("We use Plaid to securely connect your bank account and handle all payment processing.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(BlueprintTheme.accentAqua.opacity(0.1))
                    )
                    .padding(.horizontal)
                    
                    Spacer(minLength: 40)
                    
                    // Connect Button
                    VStack(spacing: 12) {
                        Button {
                            showPlaidSimulation = true
                        } label: {
                            HStack {
                                if isConnectingPlaid {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "link.circle.fill")
                                    Text("Connect with Plaid")
                                }
                            }
                        }
                        .buttonStyle(BlueprintPrimaryButtonStyle())
                        .disabled(isConnectingPlaid || viewModel.isLoading)
                        
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                    }
                    .padding(.horizontal)
                    
                    // Legal text
                    VStack(spacing: 8) {
                        Text("By connecting your account, you agree to")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 8) {
                            Link("Plaid Terms", destination: URL(string: "https://plaid.com/legal")!)
                                .font(.caption2)
                            
                            Text("•")
                                .foregroundStyle(.secondary)
                            
                            Link("Stripe Terms", destination: URL(string: "https://stripe.com/legal")!)
                                .font(.caption2)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Bank Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .blueprintScreenBackground()
        }
        .sheet(isPresented: $showPlaidSimulation) {
            PlaidLinkSimulationView(
                isConnecting: $isConnectingPlaid,
                onConnect: handlePlaidConnection
            )
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.showError = false
            }
        } message: {
            if let error = viewModel.error {
                Text(error.errorDescription ?? "An error occurred")
            }
        }
    }
    
    private func handlePlaidConnection(bankName: String, accountId: String) {
        Task {
            await viewModel.connectPlaidBank(
                publicToken: "public_token_from_plaid",
                accountId: accountId,
                bankName: bankName
            )
            if viewModel.billingInfo != nil {
                dismiss()
            }
        }
    }
}

// MARK: - Plaid Link Simulation
struct PlaidLinkSimulationView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isConnecting: Bool
    
    let onConnect: (String, String) -> Void
    
    @State private var selectedBank = "Chase Bank"
    @State private var selectedAccountId = "acc_1234567890"
    
    let availableBanks = [
        ("Chase Bank", "acc_chase_001"),
        ("Bank of America", "acc_bofa_002"),
        ("Wells Fargo", "acc_wells_003"),
        ("Citibank", "acc_citi_004"),
        ("US Bank", "acc_usbank_005"),
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "building.2.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(BlueprintTheme.primary)
                    
                    Text("Plaid Link Simulation")
                        .font(.headline)
                    
                    Text("Select a bank to connect")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                
                VStack(spacing: 12) {
                    Text("Select Your Bank")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    Picker("Bank", selection: $selectedBank) {
                        ForEach(availableBanks, id: \.0) { bank, accountId in
                            Text(bank).tag(bank)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 150)
                }
                .padding()
                
                VStack(spacing: 12) {
                    Text("Account Details")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    BlueprintCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Bank Name")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(selectedBank)
                                    .fontWeight(.semibold)
                            }
                            
                            Divider()
                            
                            HStack {
                                Text("Account Type")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Checking")
                                    .fontWeight(.semibold)
                            }
                            
                            Divider()
                            
                            HStack {
                                Text("Account Number")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("••••7890")
                                    .fontWeight(.semibold)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button {
                        isConnecting = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            await MainActor.run {
                                if let (bankName, accountId) = availableBanks.first(where: { $0.0 == selectedBank }) {
                                    onConnect(bankName, accountId)
                                    isConnecting = false
                                    dismiss()
                                }
                            }
                        }
                    } label: {
                        HStack {
                            if isConnecting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Confirm & Connect")
                            }
                        }
                    }
                    .buttonStyle(BlueprintPrimaryButtonStyle())
                    .disabled(isConnecting)
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Connect Bank")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(BlueprintTheme.primary)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(BlueprintTheme.surfaceElevated)
        )
    }
}

#Preview {
    StripeBillingSetupView(viewModel: SettingsViewModel())
}

