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
    @State private var activeCategory: String? = nil

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
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        pageHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 20)

                        statusBanners
                            .padding(.bottom, statusBannerCount > 0 ? 24 : 0)

                        featuredSection
                            .padding(.bottom, 28)

                        categoryFilterRow
                            .padding(.bottom, 16)

                        allCapturesSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 28)

                        submissionsRow
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)

                        submitSpaceRow
                            .padding(.horizontal, 20)
                            .padding(.bottom, 48)
                    }
                }
                .refreshable { await viewModel.refresh() }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showConnectSheet) {
            GlassesConnectSheet(glassesManager: glassesManager) { showConnectSheet = false }
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

    // MARK: - Page Header

    private var pageHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Captures")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                Text("Scan spaces near you and earn")
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.5))
            }
            Spacer()
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(white: 0.6))
                    .frame(width: 38, height: 38)
                    .background(Color(white: 0.12), in: Circle())
            }
        }
    }

    // MARK: - Status Banners

    private var statusBannerCount: Int {
        var count = 0
        if !isGlassesConnected { count += 1 }
        if !payoutsReady { count += 1 }
        return count
    }

    @ViewBuilder
    private var statusBanners: some View {
        VStack(spacing: 8) {
            if !isGlassesConnected {
                kledBanner(
                    icon: "eyeglasses",
                    title: glassesStatusTitle,
                    subtitle: glassesStatusSubtitle,
                    tone: .neutral,
                    actionTitle: "Connect"
                ) { showConnectSheet = true }
                .padding(.horizontal, 20)
            }
            if !payoutsReady {
                kledBanner(
                    icon: "creditcard.fill",
                    title: "No payout method connected",
                    subtitle: "Connect a payout method to receive earnings.",
                    tone: .warning,
                    actionTitle: "Connect"
                ) { showingStripeOnboarding = true }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Featured Section

    private var featuredItems: [ScanHomeViewModel.JobItem] {
        let specials = viewModel.specialItems
        let readyNearby = viewModel.nearbyItems.filter { $0.isReadyNow && $0.permissionTier == .approved }
        let combined = specials + readyNearby
        return Array(combined.prefix(10))
    }

    @ViewBuilder
    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Featured Captures")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                if !featuredItems.isEmpty {
                    Text("\(featuredItems.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(white: 0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(white: 0.15), in: Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, 20)

            switch viewModel.state {
            case .idle, .loading:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(0..<3, id: \.self) { _ in
                            ShimmerFeaturedCard()
                        }
                    }
                    .padding(.horizontal, 20)
                }
            case .error(let msg):
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.4))
                    .padding(.horizontal, 20)
            case .loaded:
                if featuredItems.isEmpty {
                    emptyFeaturedPlaceholder
                        .padding(.horizontal, 20)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(featuredItems) { item in
                                Button { selectedItem = item } label: {
                                    FeaturedCaptureCard(item: item)
                                        .frame(width: 280)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var emptyFeaturedPlaceholder: some View {
        HStack(spacing: 14) {
            Image(systemName: "mappin.and.ellipse")
                .font(.title2)
                .foregroundStyle(Color(white: 0.3))
            Text("No featured captures near you right now.")
                .font(.subheadline)
                .foregroundStyle(Color(white: 0.4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Category Filter

    private var allCategories: [String] {
        let cats = viewModel.items.compactMap { $0.job.category }
        let unique = Array(NSOrderedSet(array: cats).array as? [String] ?? cats)
        return unique
    }

    @ViewBuilder
    private var categoryFilterRow: some View {
        if !allCategories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    CategoryPill(label: "All", isSelected: activeCategory == nil) {
                        activeCategory = nil
                    }
                    ForEach(allCategories, id: \.self) { cat in
                        CategoryPill(label: cat.uppercased(), isSelected: activeCategory == cat) {
                            activeCategory = activeCategory == cat ? nil : cat
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - All Captures Section

    private var filteredNearbyItems: [ScanHomeViewModel.JobItem] {
        let base = viewModel.nearbyItems
        guard let cat = activeCategory else { return base }
        return base.filter { $0.job.category == cat }
    }

    private var filteredSpecialItems: [ScanHomeViewModel.JobItem] {
        let base = viewModel.specialItems
        guard let cat = activeCategory else { return base }
        return base.filter { $0.job.category == cat }
    }

    @ViewBuilder
    private var allCapturesSection: some View {
        let allItems: [ScanHomeViewModel.JobItem] = {
            var result: [ScanHomeViewModel.JobItem] = []
            result.append(contentsOf: filteredSpecialItems.filter { item in
                !featuredItems.contains(where: { $0.id == item.id })
            })
            result.append(contentsOf: filteredNearbyItems.filter { item in
                !featuredItems.contains(where: { $0.id == item.id })
            })
            return result
        }()

        if !allItems.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("All Captures")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("\(allItems.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(white: 0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(white: 0.15), in: Capsule())
                    Spacer()
                }

                LazyVStack(spacing: 12) {
                    ForEach(allItems) { item in
                        Button { selectedItem = item } label: {
                            CaptureListRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Submissions Row

    @ViewBuilder
    private var submissionsRow: some View {
        let summary = viewModel.submissionSummary.filter { $0.count > 0 }
        if !summary.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("My Submissions")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 10) {
                    ForEach(summary) { item in
                        SubmissionPill(item: item)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Submit Space Row

    private var submitSpaceRow: some View {
        Button {
            reviewSubmissionSeed = SpaceReviewSeed(title: "Open capture review")
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundStyle(BlueprintTheme.brandTeal)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Submit a space for review")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Address required · Rights check · Review-gated")
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.45))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(white: 0.3))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(white: 0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kled Banner

    private func kledBanner(
        icon: String,
        title: String,
        subtitle: String,
        tone: KledBannerTone,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 0) {
            // Left accent border
            Rectangle()
                .fill(tone.accentColor)
                .frame(width: 3)
                .cornerRadius(2)

            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tone.accentColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.5))
                        .lineLimit(2)
                }

                Spacer()

                if let actionTitle {
                    Button(actionTitle, action: action)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tone.accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(tone.accentColor.opacity(0.14))
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tone.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    private enum KledBannerTone {
        case neutral, warning, good

        var accentColor: Color {
            switch self {
            case .neutral: return BlueprintTheme.brandTeal
            case .warning: return Color(red: 0.9, green: 0.55, blue: 0.1)
            case .good: return BlueprintTheme.successGreen
            }
        }
    }

    // MARK: - Helpers

    private var isGlassesConnected: Bool {
        if case .connected = glassesManager.connectionState { return true }
        return false
    }

    private var glassesStatusTitle: String {
        switch glassesManager.connectionState {
        case .connected: return "Capture glasses ready"
        case .connecting: return "Connecting glasses"
        case .scanning: return "Scanning for glasses"
        case .error: return "Connection issue"
        case .disconnected: return "Connect capture glasses"
        }
    }

    private var glassesStatusSubtitle: String {
        switch glassesManager.connectionState {
        case .connected(let name): return name
        case .connecting: return "Keep the device nearby."
        case .scanning: return "Looking for paired devices."
        case .error(let message): return message
        case .disconnected: return "Required for approved capture opportunities."
        }
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
        if let url = URL(string: "http://maps.apple.com/?daddr=\(job.lat),\(job.lng)&dirflg=d") {
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
        guard Auth.auth().currentUser != nil else { payoutsReady = false; return }
        do {
            let state = try await StripeConnectService.shared.fetchAccountState()
            payoutsReady = state.isReadyForTransfers
        } catch {
            payoutsReady = false
        }
    }
}

// MARK: - Featured Capture Card (Kled-style full-bleed)

private struct FeaturedCaptureCard: View {
    let item: ScanHomeViewModel.JobItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Artwork
            CaptureCardArtwork(item: item)
                .frame(height: 230)

            // Gradient overlay
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.82)],
                startPoint: .center,
                endPoint: .bottom
            )

            // Content overlay
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if let cat = item.job.category {
                        CategoryTag(label: cat.uppercased())
                    }
                    Spacer()
                    PermissionDot(tier: item.permissionTier)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.job.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(item.job.address)
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.65))
                        .lineLimit(1)

                    HStack(spacing: 12) {
                        CardMetric(text: item.payoutLabel, icon: "dollarsign.circle.fill", color: BlueprintTheme.successGreen)
                        CardMetric(text: item.distanceLabel, icon: "location.fill", color: item.isReadyNow ? BlueprintTheme.brandTeal : Color(white: 0.55))
                        CardMetric(text: "\(item.job.estMinutes) min", icon: "clock", color: Color(white: 0.55))
                    }
                }

                // View button
                HStack {
                    Text("View capture")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.caption)
                        .foregroundStyle(BlueprintTheme.brandTeal)
                }
            }
            .padding(16)
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(white: 0.15), lineWidth: 1)
        )
    }
}

// MARK: - Capture List Row (Kled "All Special Tasks" style)

private struct CaptureListRow: View {
    let item: ScanHomeViewModel.JobItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CaptureCardArtwork(item: item)
                .frame(height: 120)

            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.86)],
                startPoint: .center,
                endPoint: .bottom
            )

            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    if let cat = item.job.category {
                        CategoryTag(label: cat.uppercased())
                    }
                    Text(item.job.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(item.job.address)
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.6))
                        .lineLimit(1)
                }
                .padding(12)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(item.payoutLabel)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BlueprintTheme.successGreen)
                    Text(item.distanceLabel)
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.5))
                }
                .padding(.trailing, 14)
                .padding(.bottom, 12)
            }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(white: 0.12), lineWidth: 1)
        )
    }
}

// MARK: - Submission Pill

private struct SubmissionPill: View {
    let item: ScanHomeViewModel.SubmissionSummaryItem

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.stage.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(pillColor)
            Text("\(item.count) \(item.stage.title)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.1), in: Capsule())
        .overlay(Capsule().stroke(pillColor.opacity(0.3), lineWidth: 1))
    }

    private var pillColor: Color {
        switch item.stage {
        case .inReview: return BlueprintTheme.brandTeal
        case .needsRecapture: return .orange
        case .paid: return BlueprintTheme.successGreen
        }
    }
}

// MARK: - Category Filter Pill

private struct CategoryPill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .black : Color(white: 0.65))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(isSelected ? .white : Color(white: 0.15))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Tag (overlaid on images)

private struct CategoryTag: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color(white: 0.18), in: Capsule())
    }
}

// MARK: - Permission Dot

private struct PermissionDot: View {
    let tier: ScanHomeViewModel.CapturePermissionTier

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(tier.shortLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color(white: 0.18), in: Capsule())
    }

    private var color: Color {
        switch tier {
        case .approved: return BlueprintTheme.successGreen
        case .reviewRequired: return BlueprintTheme.brandTeal
        case .permissionRequired: return .orange
        case .blocked: return .red
        }
    }
}

// MARK: - Card Metric

private struct CardMetric: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .foregroundStyle(Color(white: 0.8))
        }
        .font(.caption.weight(.semibold))
    }
}

// MARK: - Capture Card Artwork

private struct CaptureCardArtwork: View {
    let item: ScanHomeViewModel.JobItem

    var body: some View {
        Group {
            if let url = item.previewURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        fallback
                    case .empty:
                        fallback.overlay(ProgressView().tint(.white))
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
    }

    private var fallback: some View {
        MapSnapshotView(coordinate: item.job.coordinate)
    }
}

// MARK: - Shimmer Placeholder

private struct ShimmerFeaturedCard: View {
    @State private var shimmerOffset: CGFloat = -1.0

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(white: 0.1))
            .frame(width: 280, height: 230)
            .overlay(
                LinearGradient(
                    colors: [Color.clear, Color(white: 0.18), Color.clear],
                    startPoint: .init(x: shimmerOffset, y: 0),
                    endPoint: .init(x: shimmerOffset + 0.6, y: 0)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1.5
                }
            }
    }
}

// MARK: - String Extension

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
