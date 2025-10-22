import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingBillingSetup = false
    @State private var showingStripeOnboarding = false
    @State private var showingEditProfile = false

    private var recentCaptures: [CaptureHistoryEntry] {
        Array(
            viewModel.captureHistory
                .sorted { $0.capturedAt > $1.capturedAt }
                .prefix(5)
        )
    }

    private var upcomingPayouts: [PayoutLedgerEntry] {
        Array(
            viewModel.payoutLedger
                .filter { $0.isUpcoming }
                .sorted { $0.scheduledFor < $1.scheduledFor }
                .prefix(4)
        )
    }
    
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

                    // Capture Activity
                    BlueprintCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "video.fill")
                                    .font(.title2)
                                    .foregroundStyle(BlueprintTheme.accentAqua)

                                Text("Recent Captures")
                                    .font(.headline)

                                Spacer()
                            }

                            Divider()

                            if recentCaptures.isEmpty {
                                Text("No captures yet. Your completed scans will appear here with their review status.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 16) {
                                    ForEach(Array(recentCaptures.enumerated()), id: \.element.id) { index, entry in
                                        CaptureHistoryRow(entry: entry)
                                        if index < recentCaptures.count - 1 {
                                            Divider()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if let qcStatus = viewModel.qcStatus {
                        BlueprintCard {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.title2)
                                        .foregroundStyle(BlueprintTheme.successGreen)

                                    Text("Quality Control")
                                        .font(.headline)

                                    Spacer()
                                }

                                Divider()

                                QCStatusSummary(status: qcStatus)
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

                    BlueprintCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.title2)
                                    .foregroundStyle(BlueprintTheme.primary)

                                Text("Upcoming Payouts")
                                    .font(.headline)

                                Spacer()
                            }

                            Divider()

                            if upcomingPayouts.isEmpty {
                                Text("No transfers scheduled. Once QC approves your captures you'll see payout dates here.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 16) {
                                    ForEach(Array(upcomingPayouts.enumerated()), id: \.element.id) { index, entry in
                                        UpcomingPayoutRow(entry: entry)
                                        if index < upcomingPayouts.count - 1 {
                                            Divider()
                                        }
                                    }
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

                            VStack(alignment: .leading, spacing: 16) {
                                if let billingInfo = viewModel.billingInfo {
                                    VStack(spacing: 16) {
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

                                if let stripeState = viewModel.stripeAccountState {
                                    Divider()
                                    StripeAccountStatusSummary(state: stripeState)
                                }
                            }

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

// MARK: - Subviews

private struct CaptureHistoryRow: View {
    let entry: CaptureHistoryEntry

    private var timestampFormat: Date.FormatStyle {
        .dateTime.month(.abbreviated).day().year().hour(.twoDigits(amPM: .abbreviated)).minute()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let url = entry.thumbnailURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.15))
                        .overlay { ProgressView().controlSize(.small) }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.targetAddress)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                Text(entry.capturedAt.formatted(timestampFormat))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let payout = entry.estimatedPayout {
                    Text("Est. payout \(payout, format: .currency(code: \"USD\"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            CaptureStatusBadge(status: entry.status)
        }
    }
}

private struct CaptureStatusBadge: View {
    let status: CaptureStatus

    var body: some View {
        Label {
            Text(status.displayTitle)
        } icon: {
            Image(systemName: status.iconName)
        }
        .font(.caption.bold())
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(status.tintColor.opacity(0.12)))
        .foregroundStyle(status.tintColor)
    }
}

private struct QCStatusSummary: View {
    let status: QualityControlStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                MetricPill(title: "Pending", value: "\(status.pendingCount)", color: BlueprintTheme.primary)
                MetricPill(title: "Needs Fix", value: "\(status.needsFixCount)", color: BlueprintTheme.warningOrange)
                MetricPill(title: "Approved", value: "\(status.approvedCount)", color: BlueprintTheme.successGreen)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Avg review time \(status.averageTurnaroundHours, format: .number.precision(.fractionLength(1))) hrs")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Approval rate \(status.approvalRate, format: .percent.precision(.fractionLength(1)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Updated \(status.lastUpdated, format: .relative(presentation: .numeric))")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
        }
    }
}

private struct MetricPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.08))
        )
    }
}

private struct UpcomingPayoutRow: View {
    let entry: PayoutLedgerEntry

    private var dateFormat: Date.FormatStyle {
        .dateTime.month(.abbreviated).day().year()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.scheduledFor.formatted(dateFormat))
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(entry.amount, format: .currency(code: "USD"))
                        .font(.headline)
                        .foregroundStyle(BlueprintTheme.successGreen)

                    if let description = entry.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                PayoutStatusBadge(status: entry.status)
            }
        }
    }
}

private struct PayoutStatusBadge: View {
    let status: PayoutLedgerStatus

    var body: some View {
        Label {
            Text(status.displayTitle)
        } icon: {
            Image(systemName: status.iconName)
        }
        .font(.caption.bold())
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(status.tintColor.opacity(0.12)))
        .foregroundStyle(status.tintColor)
    }
}

private struct StripeAccountStatusSummary: View {
    let state: StripeAccountState

    private var nextPayoutDateStyle: Date.FormatStyle {
        .dateTime.month(.abbreviated).day().year()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(state.isReadyForTransfers ? "Stripe account active" : "Complete onboarding")
                    .fontWeight(.semibold)
            } icon: {
                Image(systemName: state.isReadyForTransfers ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
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
                    Text("Next payout \(next.estimatedArrival.formatted(nextPayoutDateStyle)) · \(next.amount, format: .currency(code: \"USD\"))")
                } icon: {
                    Image(systemName: "calendar.badge.clock")
                }
                .foregroundStyle(.secondary)
            }

            Label {
                Text(state.instantPayoutEligible ? "Instant payouts available" : "Instant payouts locked")
            } icon: {
                Image(systemName: "bolt.fill")
            }
            .foregroundStyle(state.instantPayoutEligible ? BlueprintTheme.accentAqua : .secondary)

            if let requirements = state.requirementsDue, !requirements.isEmpty {
                Text("Pending: \(requirements.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(BlueprintTheme.warningOrange)
            }
        }
    }
}

// MARK: - Style Extensions

private extension CaptureStatus {
    var displayTitle: String {
        switch self {
        case .processing: return "Processing"
        case .qc: return "QC Review"
        case .approved: return "Approved"
        case .needsFix: return "Needs Fix"
        }
    }

    var iconName: String {
        switch self {
        case .processing: return "clock.arrow.2.circlepath"
        case .qc: return "checkmark.magnifyingglass"
        case .approved: return "checkmark.seal.fill"
        case .needsFix: return "wrench.and.screwdriver"
        }
    }

    var tintColor: Color {
        switch self {
        case .processing: return BlueprintTheme.accentAqua
        case .qc: return BlueprintTheme.primary
        case .approved: return BlueprintTheme.successGreen
        case .needsFix: return BlueprintTheme.warningOrange
        }
    }
}

private extension PayoutLedgerStatus {
    var displayTitle: String {
        switch self {
        case .pending: return "Scheduled"
        case .inTransit: return "In Transit"
        case .paid: return "Paid"
        case .failed: return "Failed"
        }
    }

    var iconName: String {
        switch self {
        case .pending: return "clock"
        case .inTransit: return "arrow.triangle.2.circlepath"
        case .paid: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .pending: return BlueprintTheme.primary
        case .inTransit: return BlueprintTheme.accentAqua
        case .paid: return BlueprintTheme.successGreen
        case .failed: return BlueprintTheme.errorRed
        }
    }
}

