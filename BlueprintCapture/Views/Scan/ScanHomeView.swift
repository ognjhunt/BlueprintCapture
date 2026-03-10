import SwiftUI
import FirebaseAuth
import UIKit

struct ScanHomeView: View {
    @ObservedObject var glassesManager: GlassesCaptureManager
    @ObservedObject var uploadQueue: UploadQueueViewModel
    @ObservedObject var alertsManager: NearbyAlertsManager

    @StateObject private var viewModel: ScanHomeViewModel

    @State private var selectedItem: ScanHomeViewModel.JobItem?
    @State private var showConnectSheet = false
    @State private var recordingJob: ScanJob?
    @State private var showAnywhereCapture = false
    @State private var pendingStartJobId: String?

    @State private var payoutsReady: Bool = false
    @State private var showingStripeOnboarding = false

    init(glassesManager: GlassesCaptureManager, uploadQueue: UploadQueueViewModel, alertsManager: NearbyAlertsManager) {
        self.glassesManager = glassesManager
        self.uploadQueue = uploadQueue
        self.alertsManager = alertsManager
        _viewModel = StateObject(wrappedValue: ScanHomeViewModel(alertsManager: alertsManager))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    glassesStatusCard

                    setupCards

                    captureAnywhereCard

                    if let ready = viewModel.readyNow {
                        readyNowCard(item: ready)
                    }

                    jobsSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .refreshable { await viewModel.refresh() }
        }
        .blueprintAppBackground()
        .sheet(isPresented: $showConnectSheet) {
            GlassesConnectSheet(glassesManager: glassesManager) {
                showConnectSheet = false
            }
        }
        .sheet(item: $selectedItem) { item in
            JobDetailSheet(
                item: item,
                userLocation: viewModel.currentLocation,
                onStartScan: { recordingJob = item.job },
                onDirections: { openDirections(to: item.job) }
            )
        }
        .fullScreenCover(item: $recordingJob) { job in
            ScanRecordingView(job: job, glassesManager: glassesManager, uploadQueue: uploadQueue)
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showAnywhereCapture) {
            AnywhereCaptureFlowView()
                .preferredColorScheme(.dark)
        }
        .alert("Error", isPresented: $viewModel.showErrorAlert) {
            Button("OK", role: .cancel) { viewModel.showErrorAlert = false }
        } message: {
            Text(viewModel.errorMessage ?? "Something went wrong.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .blueprintNotificationAction)) { note in
            guard
                let info = note.userInfo as? [String: Any],
                let action = info["action"] as? String,
                action == "start_scan",
                let jobId = info["jobId"] as? String
            else { return }
            pendingStartJobId = jobId
            Task { await startFromNotificationIfPossible(jobId: jobId) }
        }
        .task {
            viewModel.onAppear()
            await refreshPayoutsReady()
            if let jobId = UserDefaults.standard.string(forKey: AppConfig.pendingStartScanJobIdKey) {
                UserDefaults.standard.removeObject(forKey: AppConfig.pendingStartScanJobIdKey)
                pendingStartJobId = jobId
                await startFromNotificationIfPossible(jobId: jobId)
            }
        }
        .onDisappear { viewModel.onDisappear() }
    }

    private var glassesStatusCard: some View {
        Button {
            if case .connected = glassesManager.connectionState {
                // no-op
            } else {
                showConnectSheet = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "eyeglasses")
                    .foregroundStyle(BlueprintTheme.brandTeal)

                VStack(alignment: .leading, spacing: 2) {
                    Text(glassesStatusTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(glassesStatusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if case .connected = glassesManager.connectionState {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BlueprintTheme.successGreen)
                } else {
                    Text("Connect")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.primary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private var glassesStatusTitle: String {
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
            return "Connect your glasses"
        }
    }

    private var glassesStatusSubtitle: String {
        switch glassesManager.connectionState {
        case .connected(let name):
            return name
        case .connecting:
            return "Keep glasses nearby"
        case .scanning:
            return "Looking for devices"
        case .error(let message):
            return message
        case .disconnected:
            return "Required for scanning"
        }
    }

    @ViewBuilder
    private var setupCards: some View {
        VStack(spacing: 12) {
            if !alertsManager.isAlwaysAuthorized {
                setupCard(
                    title: "Enable Nearby Alerts (Recommended)",
                    subtitle: "Get notified when you’re near a scan job.",
                    icon: "bell.badge.fill",
                    buttonTitle: "Enable",
                    buttonStyle: .primary
                ) {
                    alertsManager.requestAlwaysAuthorization()
                }
            }

            if !payoutsReady {
                setupCard(
                    title: "Connect payouts",
                    subtitle: "Get paid after QC approves your scan.",
                    icon: "creditcard.fill",
                    buttonTitle: "Connect",
                    buttonStyle: .secondary
                ) {
                    showingStripeOnboarding = true
                }
                .sheet(isPresented: $showingStripeOnboarding) {
                    StripeOnboardingView()
                }
            }
        }
    }

    private var captureAnywhereCard: some View {
        Button {
            showAnywhereCapture = true
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Capture anywhere", systemImage: "camera.metering.center.weighted")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Use your iPhone to record the space around you, even when there isn’t a curated job nearby.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        tag(text: "iPhone")
                        tag(text: "Phase 1")
                        tag(text: "Exportable")
                    }
                }

                Spacer()

                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(BlueprintTheme.brandTeal)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(.secondarySystemBackground), BlueprintTheme.brandTeal.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func tag(text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(BlueprintTheme.brandTeal)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(BlueprintTheme.brandTeal.opacity(0.12))
            )
    }

    private enum SetupButtonStyle { case primary, secondary }

    private func setupCard(title: String, subtitle: String, icon: String, buttonTitle: String, buttonStyle: SetupButtonStyle, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(BlueprintTheme.brandTeal)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(buttonTitle, action: action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(buttonStyle == .primary ? .white : BlueprintTheme.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(buttonStyle == .primary ? BlueprintTheme.primary : Color(.systemFill))
                )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func readyNowCard(item: ScanHomeViewModel.JobItem) -> some View {
        Button {
            recordingJob = item.job
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Ready now")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("$\(item.job.payoutDollars)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BlueprintTheme.successGreen)
                }

                Text(item.job.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Label("\(item.job.estMinutes) min", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("\(String(format: "%.1f", item.distanceMiles)) mi", systemImage: "location")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Start scan")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(BlueprintTheme.successGreen))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [BlueprintTheme.primary.opacity(0.25), BlueprintTheme.brandTeal.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var jobsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Nearby jobs")
                    .font(.headline)
                Spacer()
                if let ts = viewModel.lastUpdatedAt {
                    Text(ts.formatted(.dateTime.hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            switch viewModel.state {
            case .idle, .loading:
                HStack(spacing: 12) {
                    ProgressView().tint(BlueprintTheme.brandTeal)
                    Text("Finding jobs…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )

            case .error(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn’t load jobs")
                        .font(.headline)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Try again") { Task { await viewModel.refresh() } }
                        .buttonStyle(BlueprintPrimaryButtonStyle())
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )

            case .loaded:
                if viewModel.items.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No curated jobs nearby.")
                            .font(.subheadline.weight(.semibold))
                        Text("Try again later or change location.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.items) { item in
                            Button {
                                selectedItem = item
                            } label: {
                                ScanJobRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func openDirections(to job: ScanJob) {
        let lat = job.lat
        let lng = job.lng
        if let url = URL(string: "http://maps.apple.com/?daddr=\(lat),\(lng)&dirflg=d") {
            UIApplication.shared.open(url)
        }
    }

    private func startFromNotificationIfPossible(jobId: String) async {
        // Try immediately from current feed
        if let match = viewModel.items.first(where: { $0.job.id == jobId }) {
            recordingJob = match.job
            pendingStartJobId = nil
            return
        }

        // Force refresh once, then retry.
        await viewModel.refresh()
        if let match = viewModel.items.first(where: { $0.job.id == jobId }) {
            recordingJob = match.job
            pendingStartJobId = nil
        }
    }

    private func refreshPayoutsReady() async {
        guard Auth.auth().currentUser != nil else {
            payoutsReady = false
            return
        }
        do {
            let state = try await StripeConnectService.shared.fetchAccountState()
            payoutsReady = state.isReadyForTransfers
        } catch {
            payoutsReady = false
        }
    }
}

private struct ScanJobRow: View {
    let item: ScanHomeViewModel.JobItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.job.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Text("$\(item.job.payoutDollars)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.successGreen)
                    Text("\(item.job.estMinutes) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f", item.distanceMiles)) mi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if item.isReadyNow {
                Text("Now")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(BlueprintTheme.successGreen.opacity(0.15)))
                    .foregroundStyle(BlueprintTheme.successGreen)
            } else if let badge = item.statusBadge {
                Text(badge)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(.systemFill)))
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
