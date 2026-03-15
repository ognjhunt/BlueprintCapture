import SwiftUI

struct WalletView: View {
    @ObservedObject var glassesManager: GlassesCaptureManager
    @StateObject private var viewModel = WalletViewModel()

    @State private var showingStripeOnboarding = false
    @State private var showingAuth = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    earningsCard

                    if let qc = viewModel.qcStatus {
                        qcCard(qc)
                    }

                    if let state = viewModel.stripeAccountState, !state.isReadyForTransfers {
                        connectPayoutsCard
                    } else if viewModel.stripeAccountState == nil {
                        connectPayoutsCard
                    }

                    captureHistoryCard

                    payoutLedgerCard

                    devicesCard

                    accountCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .navigationTitle("Wallet")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .refreshable { await viewModel.load() }
        }
        .blueprintAppBackground()
        .sheet(isPresented: $showingStripeOnboarding) {
            StripeOnboardingView()
        }
        .sheet(isPresented: $showingAuth) {
            AuthView()
        }
        .task { await viewModel.load() }
        .alert("Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }

    private var earningsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Earnings", systemImage: "dollarsign.circle.fill")
                    .font(.headline)
                Spacer()
                if viewModel.isLoading {
                    ProgressView().tint(BlueprintTheme.brandTeal)
                }
            }

            HStack(spacing: 0) {
                stat(value: viewModel.totalEarnings, label: "Total", color: BlueprintTheme.successGreen)
                Divider().frame(height: 36)
                stat(value: viewModel.pendingPayout, label: "Pending", color: BlueprintTheme.primary)
                Divider().frame(height: 36)
                VStack(spacing: 4) {
                    Text("\(viewModel.scansCompleted)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("Scans")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func stat(value: Decimal, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value, format: .currency(code: "USD"))
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func qcCard(_ qc: QualityControlStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Quality Control", systemImage: "checkmark.shield.fill")
                .font(.headline)

            HStack {
                qcStat("\(qc.pendingCount)", label: "Pending")
                qcStat("\(qc.needsFixCount)", label: "Needs Fix")
                qcStat("\(qc.approvedCount)", label: "Approved")
            }

            Text("Avg turnaround: \(String(format: "%.0f", qc.averageTurnaroundHours))h")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func qcStat(_ value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var connectPayoutsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Connect payouts", systemImage: "creditcard.fill")
                .font(.headline)

            Text("Connect your bank account to receive payouts after QC approves your scans.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Connect with Stripe") {
                showingStripeOnboarding = true
            }
            .buttonStyle(BlueprintPrimaryButtonStyle())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var captureHistoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Capture History", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            if viewModel.captureHistory.isEmpty {
                Text(viewModel.isAuthenticated ? "No captures yet." : "Log in to see your history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.captureHistory.prefix(8)) { entry in
                    NavigationLink {
                        CaptureDetailView(entry: entry)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.targetAddress)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(entry.statusLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let payout = entry.estimatedPayout {
                                Text(payout, format: .currency(code: "USD"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BlueprintTheme.successGreen)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var payoutLedgerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Payouts", systemImage: "banknote.fill")
                .font(.headline)

            if viewModel.payoutLedger.isEmpty {
                Text(viewModel.isAuthenticated ? "No payouts yet." : "Log in to see payouts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.payoutLedger.prefix(6)) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.scheduledFor.formatted(.dateTime.month().day().year()))
                                .font(.subheadline.weight(.medium))
                            Text(entry.statusLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.amount, format: .currency(code: "USD"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    Divider()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var devicesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Devices", systemImage: "eyeglasses")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(deviceTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(deviceSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()

                if case .connected = glassesManager.connectionState {
                    Button("Disconnect") { glassesManager.disconnect() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.primary)
                } else if glassesManager.lastConnectedDevice != nil {
                    Button("Reconnect") { glassesManager.reconnectLastDevice() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.primary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var deviceTitle: String {
        switch glassesManager.connectionState {
        case .connected:
            return "Glasses connected"
        case .connecting:
            return "Connecting…"
        case .scanning:
            return "Scanning…"
        case .error:
            return "Connection error"
        case .disconnected:
            return "Not connected"
        }
    }

    private var deviceSubtitle: String {
        switch glassesManager.connectionState {
        case .connected(let name):
            return name
        case .error(let message):
            return message
        default:
            return glassesManager.lastConnectedDevice?.name ?? "Meta smart glasses required for scans"
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Account", systemImage: "person.crop.circle")
                .font(.headline)

            if viewModel.isAuthenticated {
                Button(role: .destructive) {
                    Task { await viewModel.signOut() }
                } label: {
                    Text("Sign Out")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BlueprintSecondaryButtonStyle())
            } else {
                Button {
                    showingAuth = true
                } label: {
                    Text("Sign Up / Log In")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BlueprintPrimaryButtonStyle())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private extension CaptureHistoryEntry {
    var statusLabel: String {
        switch status {
        case .draft: return "Draft"
        case .readyToSubmit: return "Ready to submit"
        case .submitted: return "Submitted"
        case .underReview: return "Under review"
        case .processing: return "Processing"
        case .qc: return "Quality check"
        case .approved: return "Approved"
        case .needsRecapture: return "Needs recapture"
        case .needsFix: return "Needs fix"
        case .rejected: return "Rejected"
        case .paid: return "Paid"
        }
    }
}

private extension PayoutLedgerEntry {
    var statusLabel: String {
        switch status {
        case .pending: return "Pending"
        case .inTransit: return "In transit"
        case .paid: return "Paid"
        case .failed: return "Failed"
        }
    }
}
