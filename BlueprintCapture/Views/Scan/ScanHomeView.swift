import SwiftUI
import FirebaseAuth
import UIKit

struct ScanHomeView: View {
    @ObservedObject var glassesManager: GlassesCaptureManager
    @ObservedObject var uploadQueue: UploadQueueViewModel
    @ObservedObject var alertsManager: NearbyAlertsManager

    @StateObject private var viewModel: ScanHomeViewModel

    @State private var selectedItem: ScanHomeViewModel.JobItem?
    @State private var reviewSubmissionSeed: SpaceReviewSeed?
    @State private var showConnectSheet = false
    @State private var recordingJob: ScanJob?
    @State private var pendingStartJobId: String?

    @State private var payoutsReady = false
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
                VStack(alignment: .leading, spacing: 22) {
                    introHeader
                    statusBanners

                    if let ready = viewModel.readyNow {
                        readyNearbySection(item: ready)
                    }

                    if !viewModel.nearbyItems.isEmpty {
                        nearbySection
                    }

                    if !viewModel.specialItems.isEmpty {
                        specialCapturesSection
                    }

                    submissionsSection
                    reviewSubmissionSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .navigationTitle("Capture")
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
        .sheet(isPresented: $showingStripeOnboarding) {
            StripeOnboardingView()
        }
        .sheet(item: $selectedItem) { item in
            JobDetailSheet(
                item: item,
                userLocation: viewModel.currentLocation,
                onStartCapture: { recordingJob = item.job },
                onSubmitForReview: { reviewSubmissionSeed = submissionSeed(for: item) },
                onDirections: { openDirections(to: item.job) }
            )
        }
        .fullScreenCover(item: $recordingJob) { job in
            ScanRecordingView(job: job, glassesManager: glassesManager, uploadQueue: uploadQueue)
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(item: $reviewSubmissionSeed) { seed in
            AnywhereCaptureFlowView(seed: seed)
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

    private var introHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Managed alpha capture network")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BlueprintTheme.brandTeal)
                .textCase(.uppercase)

            Text("Capture approved spaces, discover special opportunities nearby, and keep every submission moving.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                capsuleTag("Near you")
                capsuleTag("Special captures")
                capsuleTag("Review status")
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(.secondarySystemBackground),
                            BlueprintTheme.brandTeal.opacity(0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusBanners: some View {
        VStack(spacing: 10) {
            slimBanner(
                title: glassesStatusTitle,
                subtitle: glassesStatusSubtitle,
                icon: "eyeglasses",
                tone: isGlassesConnected ? .good : .neutral,
                actionTitle: isGlassesConnected ? nil : "Connect"
            ) {
                showConnectSheet = true
            }

            if !payoutsReady {
                slimBanner(
                    title: "Connect payouts",
                    subtitle: "Approved submissions pay out faster once your transfer account is ready.",
                    icon: "creditcard.fill",
                    tone: .warning,
                    actionTitle: "Connect"
                ) {
                    showingStripeOnboarding = true
                }
            }

            slimBanner(
                title: "Capture guardrails",
                subtitle: trustAndSafetyCopy,
                icon: "checkmark.shield.fill",
                tone: .neutral,
                actionTitle: nil,
                action: {}
            )
        }
    }

    private func readyNearbySection(item: ScanHomeViewModel.JobItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Ready nearby", subtitle: "You can start this capture now.")
            Button {
                selectedItem = item
            } label: {
                FeatureCaptureCard(item: item, style: .readyNow)
            }
            .buttonStyle(.plain)
        }
    }

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Near you", subtitle: "Approved and review-gated capture opportunities within range.")

            switch viewModel.state {
            case .idle, .loading:
                loadingCard(message: "Finding nearby captures…")
            case .error(let message):
                errorCard(title: "Couldn’t load captures", message: message)
            case .loaded:
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.nearbyItems) { item in
                        Button {
                            selectedItem = item
                        } label: {
                            CaptureOpportunityRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var specialCapturesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Special captures", subtitle: "Higher-context work with stronger buyer intent.")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(viewModel.specialItems) { item in
                        Button {
                            selectedItem = item
                        } label: {
                            FeatureCaptureCard(item: item, style: .special)
                                .frame(width: 292)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var submissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Your submissions", subtitle: "Track what is in review, what needs another pass, and what already paid.")

            HStack(spacing: 12) {
                ForEach(viewModel.submissionSummary) { item in
                    SubmissionStageCard(item: item)
                }
            }
        }
    }

    private var reviewSubmissionSection: some View {
        Button {
            reviewSubmissionSeed = SpaceReviewSeed(title: "Open capture review")
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Submit a space for review")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("Use this when the space is promising but not already approved. We review the submission before it becomes a reusable capture opportunity.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(BlueprintTheme.brandTeal)
                }

                HStack(spacing: 8) {
                    capsuleTag("Address required")
                    capsuleTag("Rights check")
                    capsuleTag("Review-gated")
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func slimBanner(
        title: String,
        subtitle: String,
        icon: String,
        tone: BannerTone,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tone.color)
                .frame(width: 28, height: 28)
                .background(tone.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(tone.color)
                    )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tone.color.opacity(0.16), lineWidth: 1)
        )
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if let ts = viewModel.lastUpdatedAt {
                    Text(ts.formatted(.dateTime.hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func loadingCard(message: String) -> some View {
        HStack(spacing: 12) {
            ProgressView().tint(BlueprintTheme.brandTeal)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func errorCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
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
    }

    private func capsuleTag(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(BlueprintTheme.brandTeal)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(BlueprintTheme.brandTeal.opacity(0.14))
            )
    }

    private enum BannerTone {
        case neutral
        case warning
        case good

        var color: Color {
            switch self {
            case .neutral:
                return BlueprintTheme.brandTeal
            case .warning:
                return .orange
            case .good:
                return BlueprintTheme.successGreen
            }
        }
    }

    private var glassesStatusTitle: String {
        switch glassesManager.connectionState {
        case .connected:
            return "Capture glasses ready"
        case .connecting:
            return "Connecting glasses"
        case .scanning:
            return "Scanning for glasses"
        case .error:
            return "Connection issue"
        case .disconnected:
            return "Connect capture glasses"
        }
    }

    private var isGlassesConnected: Bool {
        if case .connected = glassesManager.connectionState {
            return true
        }
        return false
    }

    private var glassesStatusSubtitle: String {
        switch glassesManager.connectionState {
        case .connected(let name):
            return name
        case .connecting:
            return "Keep the device nearby."
        case .scanning:
            return "Looking for paired devices."
        case .error(let message):
            return message
        case .disconnected:
            return "Required for approved capture opportunities."
        }
    }

    private var trustAndSafetyCopy: String {
        if viewModel.nearbyPolicyCount(for: .blocked) > 0 {
            return "Some nearby spaces are blocked. Stick to approved areas, avoid faces and screens, and follow posted restrictions."
        }
        if viewModel.nearbyPolicyCount(for: .permissionRequired) > 0 {
            return "Some nearby spaces need extra care. Stay in common areas, keep private information out of frame, and stop if staff tells you to stop."
        }
        return "Stay in common or approved areas, avoid faces/screens, and use review submission when the capture scope is unclear."
    }

    private func submissionSeed(for item: ScanHomeViewModel.JobItem) -> SpaceReviewSeed {
        let suggestedContext = [item.job.workflowName, item.job.targetKPI, item.job.zone]
            .compactMap { $0 }
            .joined(separator: " • ")
        return SpaceReviewSeed(
            id: item.job.id,
            title: item.job.title,
            address: item.job.address,
            payoutRange: item.job.quotedPayoutCents.map { max(5, $0 / 100 - 10)...($0 / 100) },
            captureJobId: item.job.id,
            buyerRequestId: item.job.buyerRequestId,
            siteSubmissionId: item.job.siteSubmissionId,
            regionId: item.job.regionId,
            rightsProfile: item.job.rightsProfile,
            requestedOutputs: item.job.requestedOutputs.isEmpty ? ["qualification", "review_intake"] : item.job.requestedOutputs,
            suggestedContext: suggestedContext.nilIfEmpty
        )
    }

    private func openDirections(to job: ScanJob) {
        let lat = job.lat
        let lng = job.lng
        if let url = URL(string: "http://maps.apple.com/?daddr=\(lat),\(lng)&dirflg=d") {
            UIApplication.shared.open(url)
        }
    }

    private func startFromNotificationIfPossible(jobId: String) async {
        if let match = viewModel.items.first(where: { $0.job.id == jobId }),
           match.permissionTier == .approved {
            recordingJob = match.job
            pendingStartJobId = nil
            return
        }

        await viewModel.refresh()
        if let match = viewModel.items.first(where: { $0.job.id == jobId }),
           match.permissionTier == .approved {
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

private struct CaptureOpportunityRow: View {
    let item: ScanHomeViewModel.JobItem

    var body: some View {
        HStack(spacing: 14) {
            CaptureArtwork(item: item)
                .frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.job.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(item.job.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    PermissionBadge(tier: item.permissionTier)
                }

                HStack(spacing: 10) {
                    MiniMetric(label: item.payoutLabel, icon: "dollarsign.circle.fill", tint: BlueprintTheme.successGreen)
                    MiniMetric(label: "\(item.job.estMinutes) min", icon: "clock", tint: .secondary)
                    MiniMetric(label: item.distanceLabel, icon: "location", tint: item.isReadyNow ? BlueprintTheme.successGreen : .secondary)
                }

                HStack(spacing: 8) {
                    if let badge = item.availabilityBadge {
                        InlineBadge(text: badge, tone: .neutral)
                    }
                    Text(item.reviewNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct FeatureCaptureCard: View {
    enum Style {
        case readyNow
        case special
    }

    let item: ScanHomeViewModel.JobItem
    let style: Style

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CaptureArtwork(item: item)
                .frame(height: style == .readyNow ? 260 : 340)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.76)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    InlineBadge(text: style == .readyNow ? "Ready nearby" : "Special capture", tone: .teal)
                    Spacer()
                    PermissionBadge(tier: item.permissionTier)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.job.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(item.job.address)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)

                    HStack(spacing: 10) {
                        InlineMetric(text: item.payoutLabel, icon: "dollarsign.circle.fill")
                        InlineMetric(text: "\(item.job.estMinutes) min", icon: "clock")
                        InlineMetric(text: item.distanceLabel, icon: "location")
                    }

                    Text(item.reviewNote)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                }
            }
            .padding(18)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct SubmissionStageCard: View {
    let item: ScanHomeViewModel.SubmissionSummaryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: item.stage.icon)
                .font(.headline)
                .foregroundStyle(color)

            Text("\(item.count)")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            Text(item.stage.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(item.stage.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(color.opacity(0.14), lineWidth: 1)
        )
    }

    private var color: Color {
        switch item.stage {
        case .inReview:
            return BlueprintTheme.brandTeal
        case .needsRecapture:
            return .orange
        case .paid:
            return BlueprintTheme.successGreen
        }
    }
}

private struct CaptureArtwork: View {
    let item: ScanHomeViewModel.JobItem

    var body: some View {
        Group {
            if let url = item.previewURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure(_):
                        fallback
                    case .empty:
                        fallback.overlay(
                            ProgressView()
                                .tint(BlueprintTheme.brandTeal)
                        )
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .overlay(alignment: .bottomLeading) {
            if item.previewSource == .mapSnapshot {
                InlineBadge(text: "Map", tone: .neutral)
                    .padding(8)
            }
        }
    }

    private var fallback: some View {
        ZStack {
            MapSnapshotView(coordinate: item.job.coordinate)
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct PermissionBadge: View {
    let tier: ScanHomeViewModel.CapturePermissionTier

    var body: some View {
        Label(tier.shortLabel, systemImage: tier.icon)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(color.opacity(0.16))
            )
    }

    private var color: Color {
        switch tier {
        case .approved:
            return BlueprintTheme.successGreen
        case .reviewRequired:
            return BlueprintTheme.brandTeal
        case .permissionRequired:
            return .orange
        case .blocked:
            return .red
        }
    }
}

private struct InlineBadge: View {
    enum Tone {
        case neutral
        case teal
    }

    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(color.opacity(0.14))
            )
    }

    private var color: Color {
        switch tone {
        case .neutral:
            return .secondary
        case .teal:
            return BlueprintTheme.brandTeal
        }
    }
}

private struct MiniMetric: View {
    let label: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(label)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

private struct InlineMetric: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white.opacity(0.84))
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
