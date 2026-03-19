import SwiftUI
import FirebaseAuth
import UIKit
import CoreLocation
import MapKit

struct ScanHomeView: View {
    @ObservedObject var glassesManager: GlassesCaptureManager
    @ObservedObject var uploadQueue: UploadQueueViewModel
    @ObservedObject var alertsManager: NearbyAlertsManager

    @StateObject private var viewModel: ScanHomeViewModel

    @State private var selectedItem: ScanHomeViewModel.JobItem?
    @State private var reviewSubmissionSeed: SpaceReviewSeed?
    @State private var showConnectSheet = false
    @State private var recordingJob: ScanJob?
    @State private var activeCategory: String? = nil

    @State private var payoutsReady = false
    @State private var showingStripeOnboarding = false
    @State private var selectedDemo: DemoCapture?
    @State private var showingSearch = false
    @State private var nearbyPOIs: [DemoCapture] = []

    init(
        glassesManager: GlassesCaptureManager,
        uploadQueue: UploadQueueViewModel,
        alertsManager: NearbyAlertsManager,
        viewModel: ScanHomeViewModel? = nil
    ) {
        self.glassesManager = glassesManager
        self.uploadQueue = uploadQueue
        self.alertsManager = alertsManager
        _viewModel = StateObject(wrappedValue: viewModel ?? ScanHomeViewModel(alertsManager: alertsManager))
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

                        capturePolicySection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)

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
                onStartPhoneCapture: { reviewSubmissionSeed = submissionSeed(for: item) },
                onSubmitForReview: { reviewSubmissionSeed = submissionSeed(for: item) },
                onDirections: { openDirections(to: item.job) }
            )
        }
        .sheet(item: $selectedDemo) { demo in
            DemoDetailSheet(demo: demo)
        }
        .sheet(isPresented: $showingSearch) {
            CaptureSearchSheet(
                existingItems: viewModel.items,
                userLocation: viewModel.currentLocation,
                onSelectItem: { item in selectedItem = item },
                onSubmitAddress: { address, suggestedContext in
                    reviewSubmissionSeed = SpaceReviewSeed(
                        title: address,
                        address: address,
                        suggestedContext: suggestedContext
                    )
                }
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
        .onReceive(NotificationCenter.default.publisher(for: .blueprintOpenScanJobDetail)) { note in
            guard let jobId = note.userInfo?["jobId"] as? String else { return }
            Task { await openJobDetail(jobId: jobId) }
        }
        .task {
            viewModel.onAppear()
            await refreshPayoutsReady()
        }
        .onChange(of: viewModel.currentLocation) { _, loc in
            guard let loc, nearbyPOIs.isEmpty else { return }
            Task { await loadNearbyPOIs(near: loc) }
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
                Text("Capture spaces for Blueprint review")
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.5))
            }
            Spacer()
            HStack(spacing: 10) {
                Button { showingSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(white: 0.6))
                        .frame(width: 38, height: 38)
                        .background(Color(white: 0.12), in: Circle())
                }
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
                let payoutsAvailability = RuntimeConfig.current.availability(for: .payouts)
                kledBanner(
                    icon: payoutsAvailability.isEnabled ? "creditcard.fill" : "lock.shield.fill",
                    title: payoutsAvailability.isEnabled ? "No payout method connected" : "Payout setup unavailable",
                    subtitle: payoutsAvailability.message ?? "Connect a payout method to receive earnings.",
                    tone: payoutsAvailability.isEnabled ? .warning : .neutral,
                    actionTitle: payoutsAvailability.isEnabled ? "Connect" : nil
                ) { showingStripeOnboarding = true }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Featured Section

    private var featuredItems: [ScanHomeViewModel.JobItem] {
        // The alpha current-location item is always pinned first so we can test
        // the full pipeline on any live device capture.
        let alphaItem = viewModel.nearbyItems.first(where: { $0.id == ScanHomeViewModel.alphaCurrentLocationJobID })
        let specials = viewModel.specialItems
        let readyNearby = viewModel.nearbyItems.filter {
            $0.isReadyNow && $0.permissionTier == .approved
            && $0.id != ScanHomeViewModel.alphaCurrentLocationJobID
        }
        let combined = [alphaItem].compactMap { $0 } + specials + readyNearby
        return Array(combined.prefix(10))
    }

    @ViewBuilder
    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Nearby Spaces")
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
                // Always show real job cards first (includes the pinned alpha item),
                // then append the dynamic nearby POI / demo cards so they are never hidden.
                let placeholders = nearbyPOIs.isEmpty ? DemoCapture.samples : nearbyPOIs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(featuredItems.enumerated()), id: \.element.id) { index, item in
                            Button { selectedItem = item } label: {
                                FeaturedCaptureCard(item: item)
                                    .frame(width: 280)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("scan-home-featured-\(index)")
                        }
                        ForEach(placeholders) { demo in
                            Button { selectedDemo = demo } label: {
                                DemoFeaturedCard(demo: demo)
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

    // MARK: - Capture Policy

    private var capturePolicySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What you may capture")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Text("Common areas and approved opportunities are fine. Faces, screens, paperwork, and restricted zones are not.")
                .font(.subheadline)
                .foregroundStyle(Color(white: 0.55))

            HStack(spacing: 10) {
                policyPill(color: BlueprintTheme.successGreen, title: "Approved", subtitle: "Clear to capture")
                policyPill(color: BlueprintTheme.brandTeal, title: "Review", subtitle: "Needs Blueprint review")
            }
            HStack(spacing: 10) {
                policyPill(color: .orange, title: "Permission", subtitle: "Check site access")
                policyPill(color: .red, title: "Blocked", subtitle: "Do not capture")
            }
        }
    }

    private func policyPill(color: Color, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(Color(white: 0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
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
                    Text("Capture opportunities")
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
                    ForEach(Array(allItems.enumerated()), id: \.element.id) { index, item in
                        Button { selectedItem = item } label: {
                            CaptureListRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("scan-home-list-item-\(index)")
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
                    Text("Submit a new space")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Address first · Workflow notes · Review-gated")
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

    private func openJobDetail(jobId: String) async {
        if let match = viewModel.items.first(where: { $0.job.id == jobId }) {
            selectedItem = match
            return
        }
        await viewModel.refresh()
        if let match = viewModel.items.first(where: { $0.job.id == jobId }) {
            selectedItem = match
        }
    }

    private func refreshPayoutsReady() async {
        guard RuntimeConfig.current.availability(for: .payouts).isEnabled else {
            payoutsReady = false
            return
        }
        guard UserDeviceService.hasRegisteredAccount() else { payoutsReady = false; return }
        do {
            let state = try await StripeConnectService.shared.fetchAccountState()
            payoutsReady = state.isReadyForTransfers
        } catch {
            payoutsReady = false
        }
    }

    // MARK: - Nearby POI Loading

    private func loadNearbyPOIs(near userLocation: CLLocation) async {
        let region = MKCoordinateRegion(
            center: userLocation.coordinate,
            latitudinalMeters: 4000,
            longitudinalMeters: 4000
        )
        let categories: [MKPointOfInterestCategory] = [
            .store, .hotel, .parking,
            .fitnessCenter, .museum, .stadium, .publicTransport,
            .library, .theater, .movieTheater, .university
        ]
        let request = MKLocalSearch.Request()
        request.region = region
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)

        guard let response = try? await MKLocalSearch(request: request).start() else { return }

        let results: [DemoCapture] = response.mapItems.prefix(8).compactMap { item in
            guard let name = item.name else { return nil }
            let coord = item.placemark.coordinate
            let itemLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let distMiles = userLocation.distance(from: itemLoc) / 1609.34

            let street = item.placemark.thoroughfare.map { "\($0) · " } ?? ""
            let city = item.placemark.locality ?? item.placemark.administrativeArea ?? ""
            let addressLine = "\(street)\(city)".trimmingCharacters(in: .whitespaces)

            let (category, payout, minutes, colors) = poiMetadata(for: item.pointOfInterestCategory)

            return DemoCapture(
                id: "poi_\(coord.latitude)_\(coord.longitude)",
                title: name,
                address: addressLine.isEmpty ? (item.placemark.title ?? name) : addressLine,
                category: category,
                payout: payout,
                distance: String(format: "%.1f mi", distMiles),
                estMinutes: minutes,
                coordinate: coord,
                gradientColors: colors,
                permission: "Review",
                permissionColor: BlueprintTheme.brandTeal
            )
        }
        nearbyPOIs = results
    }

    private func poiMetadata(for category: MKPointOfInterestCategory?) -> (String, String, Int, [Color]) {
        switch category {
        case .store:
            return ("RETAIL", "$40", 25, [Color(red: 0.1, green: 0.18, blue: 0.28), Color(white: 0.08)])
        case .hotel:
            return ("HOSPITALITY", "$80", 40, [Color(red: 0.08, green: 0.16, blue: 0.2), Color(white: 0.08)])
        case .parking:
            return ("PARKING", "$30", 20, [Color(red: 0.18, green: 0.16, blue: 0.1), Color(white: 0.08)])
        case .fitnessCenter:
            return ("FITNESS", "$45", 30, [Color(red: 0.12, green: 0.2, blue: 0.14), Color(white: 0.08)])
        case .museum:
            return ("CULTURAL", "$65", 40, [Color(red: 0.18, green: 0.12, blue: 0.2), Color(white: 0.08)])
        case .stadium:
            return ("VENUE", "$120", 60, [Color(red: 0.2, green: 0.14, blue: 0.08), Color(white: 0.08)])
        case .publicTransport:
            return ("TRANSIT", "$50", 30, [Color(red: 0.08, green: 0.18, blue: 0.16), Color(white: 0.08)])
        case .library:
            return ("LIBRARY", "$35", 25, [Color(red: 0.12, green: 0.14, blue: 0.2), Color(white: 0.08)])
        case .theater, .movieTheater:
            return ("THEATER", "$90", 50, [Color(red: 0.2, green: 0.08, blue: 0.14), Color(white: 0.08)])
        case .university:
            return ("CAMPUS", "$55", 35, [Color(red: 0.1, green: 0.16, blue: 0.12), Color(white: 0.08)])
        default:
            return ("COMMERCIAL", "$45", 30, [Color(white: 0.18), Color(white: 0.1)])
        }
    }
}

// MARK: - Demo Placeholder Data

private struct DemoCapture: Identifiable {
    let id: String
    let title: String
    let address: String
    let category: String
    let payout: String
    let distance: String
    let estMinutes: Int
    let coordinate: CLLocationCoordinate2D
    let gradientColors: [Color]
    let permission: String
    let permissionColor: Color

    static let samples: [DemoCapture] = [
        DemoCapture(
            id: "demo_1",
            title: "Downtown Retail Space",
            address: "123 Main St · Commercial District",
            category: "RETAIL",
            payout: "$45",
            distance: "0.3 mi",
            estMinutes: 25,
            coordinate: CLLocationCoordinate2D(latitude: 37.7937, longitude: -122.3965),
            gradientColors: [Color(white: 0.18), Color(white: 0.1)],
            permission: "Approved",
            permissionColor: BlueprintTheme.successGreen
        ),
        DemoCapture(
            id: "demo_2",
            title: "Office Building Lobby",
            address: "456 Business Ave · Midtown",
            category: "COMMERCIAL",
            payout: "$60",
            distance: "0.8 mi",
            estMinutes: 35,
            coordinate: CLLocationCoordinate2D(latitude: 37.7899, longitude: -122.4014),
            gradientColors: [Color(red: 0.12, green: 0.18, blue: 0.28), Color(white: 0.08)],
            permission: "Review",
            permissionColor: BlueprintTheme.brandTeal
        ),
        DemoCapture(
            id: "demo_3",
            title: "Warehouse Floor — Special",
            address: "789 Industrial Blvd · East Side",
            category: "INDUSTRIAL",
            payout: "$120",
            distance: "2.1 mi",
            estMinutes: 60,
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.3886),
            gradientColors: [Color(red: 0.22, green: 0.14, blue: 0.08), Color(white: 0.08)],
            permission: "Special",
            permissionColor: Color(red: 0.9, green: 0.55, blue: 0.1)
        ),
    ]
}

private struct DemoFeaturedCard: View {
    let demo: DemoCapture

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CapturePreviewView(coordinate: demo.coordinate, remoteImageURL: nil)

            // Bottom gradient
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.88)],
                startPoint: .center,
                endPoint: .bottom
            )

            // Content
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(demo.category)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color(white: 0.22), in: Capsule())

                    Spacer()

                    HStack(spacing: 5) {
                        Circle().fill(demo.permissionColor).frame(width: 7, height: 7)
                        Text(demo.permission)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(white: 0.18), in: Capsule())
                }

                Spacer()

                VStack(alignment: .leading, spacing: 5) {
                    Text(demo.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(demo.address)
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.65))
                        .lineLimit(1)

                    HStack(spacing: 12) {
                        CardMetric(text: demo.payout, icon: "dollarsign.circle.fill", color: BlueprintTheme.successGreen)
                        CardMetric(text: demo.distance, icon: "location.fill", color: Color(white: 0.55))
                        CardMetric(text: "\(demo.estMinutes) min", icon: "clock", color: Color(white: 0.55))
                    }
                }

                HStack {
                    Text(demo.id.hasPrefix("poi_") ? "Nearby · Tap to submit" : "Review-only sample")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(white: 0.5))
                    Image(systemName: demo.id.hasPrefix("poi_") ? "arrow.up.circle" : "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(Color(white: 0.4))
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
                    Text("Review space")
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
        CapturePreviewView(coordinate: item.job.coordinate, remoteImageURL: item.previewURL)
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

// MARK: - Demo Detail Sheet

private struct DemoDetailSheet: View {
    let demo: DemoCapture
    @Environment(\.dismiss) private var dismiss

    private let checklist = [
        "Stay in common or approved areas only.",
        "Keep faces, screens, and paperwork out of frame.",
        "Call out restricted zones before you begin.",
        "Complete all floors before submitting."
    ]

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Hero
                    ZStack(alignment: .top) {
                        CapturePreviewView(coordinate: demo.coordinate, remoteImageURL: nil)
                        .frame(height: 320)

                        LinearGradient(
                            colors: [Color.black.opacity(0), Color.black.opacity(0.7)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        .frame(height: 320)

                        // Back button
                        HStack {
                            Button { dismiss() } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("Close")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(.ultraThinMaterial, in: Capsule())
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }

                    // Title block
                    VStack(alignment: .leading, spacing: 8) {
                        Text(demo.category)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color(white: 0.4))
                            .tracking(1.5)

                        Text(demo.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)

                        HStack(spacing: 12) {
                            Label(demo.address, systemImage: "mappin")
                                .font(.caption)
                                .foregroundStyle(Color(white: 0.5))
                        }

                        HStack(spacing: 14) {
                            demoMetric(demo.payout, icon: "dollarsign.circle.fill", color: BlueprintTheme.successGreen)
                            demoMetric(demo.distance, icon: "location.fill", color: Color(white: 0.55))
                            demoMetric("\(demo.estMinutes) min", icon: "clock", color: Color(white: 0.55))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 20)

                    // Payout banner
                    HStack(spacing: 0) {
                        Rectangle().fill(BlueprintTheme.successGreen).frame(width: 3).cornerRadius(2)
                        HStack(spacing: 10) {
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BlueprintTheme.successGreen)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Completing this capture earns \(demo.payout)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text("Paid after approval review · Usually 3–5 days")
                                    .font(.caption)
                                    .foregroundStyle(Color(white: 0.45))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(BlueprintTheme.successGreen.opacity(0.22), lineWidth: 1))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    // Requirements
                    sectionLabel("Capture Requirements")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    VStack(spacing: 0) {
                        ForEach(Array(checklist.enumerated()), id: \.offset) { idx, item in
                            HStack(alignment: .top, spacing: 12) {
                                Circle()
                                    .fill(BlueprintTheme.brandTeal)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)
                                Text(item)
                                    .font(.subheadline)
                                    .foregroundStyle(Color(white: 0.65))
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)

                            if idx < checklist.count - 1 {
                                Rectangle().fill(Color(white: 0.12)).frame(height: 1).padding(.leading, 34)
                            }
                        }
                    }
                    .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(white: 0.12), lineWidth: 1))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)

                    // CTA — demo, no action
                    HStack(spacing: 10) {
                        Image(systemName: "eye")
                            .font(.subheadline.weight(.semibold))
                        Text("Demo Capture — Sign In to Start")
                            .font(.headline.weight(.semibold))
                    }
                    .foregroundStyle(Color(white: 0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 48)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func demoMetric(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(Color(white: 0.35))
            .tracking(1.0)
    }
}

// MARK: - String Extension

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
