import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingBillingSetup = false
    @State private var showingStripeOnboarding = false
    @State private var showingEditProfile = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Section
                    BlueprintCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundStyle(BlueprintTheme.primary)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(viewModel.profile.fullName)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    
                                    Text(viewModel.profile.email)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                            }
                        }
                    }
                    
                    // Earnings Section
                    BlueprintCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "dollarsign.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(BlueprintTheme.successGreen)
                                
                                Text("Earnings")
                                    .font(.headline)
                                
                                Spacer()
                            }
                            
                            Divider()
                            
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Total Earned")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(viewModel.totalEarnings, format: .currency(code: "USD"))
                                        .font(.headline)
                                        .foregroundStyle(BlueprintTheme.successGreen)
                                }
                                
                                HStack {
                                    Text("Pending Payout")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(viewModel.pendingPayout, format: .currency(code: "USD"))
                                        .font(.headline)
                                }
                                
                                HStack {
                                    Text("Scans Completed")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(viewModel.scansCompleted)")
                                        .font(.headline)
                                }
                            }
                        }
                    }
                    
                    // Billing Info Section
                    BlueprintCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "creditcard.fill")
                                    .font(.title2)
                                    .foregroundStyle(BlueprintTheme.primary)
                                
                                Text("Billing Information")
                                    .font(.headline)
                                
                                Spacer()
                            }
                            
                            Divider()
                            
                            if let billingInfo = viewModel.billingInfo {
                                VStack(spacing: 16) {
                                    // Connected Bank Account
                                    HStack(spacing: 12) {
                                        Image(systemName: "building.columns.fill")
                                            .font(.title3)
                                            .foregroundStyle(BlueprintTheme.accentAqua)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Connected Bank Account")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                            
                                            Text("\(billingInfo.bankName) ••••\(billingInfo.lastFour)")
                                                .font(.body)
                                                .fontWeight(.medium)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(BlueprintTheme.successGreen)
                                    }
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(BlueprintTheme.surfaceElevated)
                                    )
                                    
                                    HStack(spacing: 12) {
                                        Button {
                                            showingBillingSetup = true
                                        } label: {
                                            Text("Change Bank Account")
                                        }
                                        .buttonStyle(BlueprintSecondaryButtonStyle())
                                        
                                        Button {
                                            Task {
                                                await viewModel.disconnectBankAccount()
                                            }
                                        } label: {
                                            Text("Disconnect")
                                        }
                                        .buttonStyle(BlueprintSecondaryButtonStyle())
                                    }
                                    
                                    Divider()
                                    
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Payouts")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Button {
                                            showingStripeOnboarding = true
                                        } label: {
                                            HStack { Image(systemName: "banknote.fill"); Text("Manage Payouts & Onboarding") }
                                        }
                                        .buttonStyle(BlueprintSecondaryButtonStyle())
                                    }
                                }
                            } else {
                                VStack(spacing: 16) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(BlueprintTheme.warningOrange)
                                        
                                        Text("No bank account connected")
                                            .foregroundStyle(.secondary)
                                        
                                        Spacer()
                                    }
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(BlueprintTheme.warningOrange.opacity(0.1))
                                    )
                                    
                                    Button {
                                        showingBillingSetup = true
                                    } label: {
                                        HStack {
                                            Image(systemName: "plus.circle.fill")
                                            Text("Connect Bank Account")
                                        }
                                    }
                                    .buttonStyle(BlueprintPrimaryButtonStyle())
                                    
                                    Button {
                                        showingStripeOnboarding = true
                                    } label: {
                                        HStack {
                                            Image(systemName: "banknote.fill")
                                            Text("Payouts & Onboarding")
                                        }
                                    }
                                    .buttonStyle(BlueprintSecondaryButtonStyle())
                                }
                            }
                            
                            // Stripe powered badge
                            HStack {
                                Spacer()
                                Text("Powered by")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("Stripe")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color(red: 0.38, green: 0.42, blue: 0.98))
                                Spacer()
                            }
                            .padding(.top, 8)
                        }
                    }
                    
                    // Account Settings
                    BlueprintCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "gear")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                
                                Text("Account")
                                    .font(.headline)
                                
                                Spacer()
                            }
                            
                            Divider()
                            
                            Button {
                                viewModel.startEditingProfile()
                                showingEditProfile = true
                            } label: {
                                HStack {
                                    Text("Edit Profile")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                            
                            Divider()
                            
                            Button {
                                // Privacy settings action
                            } label: {
                                HStack {
                                    Text("Privacy & Security")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                            
                            Divider()
                            
                            Button {
                                // Sign out action
                            } label: {
                                HStack {
                                    Text("Sign Out")
                                    Spacer()
                                }
                            }
                            .foregroundStyle(BlueprintTheme.errorRed)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Settings")
            .blueprintScreenBackground()
        }
        .sheet(isPresented: $showingBillingSetup) {
            StripeBillingSetupView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingStripeOnboarding) {
            StripeOnboardingView()
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView(viewModel: viewModel)
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.1))
            }
        }
        .task {
            await viewModel.loadUserData()
        }
    }
}

#Preview {
    SettingsView()
}

