import Foundation
import Combine
import CoreLocation
import CoreGraphics

protocol CaptureHistoryServiceProtocol {
    func fetchCaptureHistory() async throws -> [CaptureHistoryEntry]
}

extension APIService: CaptureHistoryServiceProtocol {}

@MainActor
final class ScanHomeViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    enum CapturePermissionTier: String, Equatable {
        case approved
        case reviewRequired
        case permissionRequired
        case blocked

        var label: String {
            switch self {
            case .approved:
                return "Approved capture"
            case .reviewRequired:
                return "Submit for review"
            case .permissionRequired:
                return "Check site access"
            case .blocked:
                return "Not allowed"
            }
        }

        var shortLabel: String {
            switch self {
            case .approved:
                return "Approved"
            case .reviewRequired:
                return "Review"
            case .permissionRequired:
                return "Check access"
            case .blocked:
                return "Blocked"
            }
        }

        var icon: String {
            switch self {
            case .approved:
                return "checkmark.shield.fill"
            case .reviewRequired:
                return "eye.trianglebadge.exclamationmark"
            case .permissionRequired:
                return "hand.raised.fill"
            case .blocked:
                return "nosign"
            }
        }
    }

    enum CaptureOpportunityKind: Equatable {
        case nearby
        case special
        case reviewSubmission

        var label: String {
            switch self {
            case .nearby:
                return "Nearby space"
            case .special:
                return "Approved opportunity"
            case .reviewSubmission:
                return "Submit a space"
            }
        }
    }

    enum PreviewSource: Equatable {
        case jobImage
        case mapSnapshot
    }

    enum CaptureSubmissionStage: String, CaseIterable, Equatable {
        case inReview
        case needsRecapture
        case paid

        var title: String {
            switch self {
            case .inReview:
                return "In review"
            case .needsRecapture:
                return "Needs recapture"
            case .paid:
                return "Paid"
            }
        }

        var subtitle: String {
            switch self {
            case .inReview:
                return "Queued, reviewing, or approved"
            case .needsRecapture:
                return "Requires another pass"
            case .paid:
                return "Completed and paid out"
            }
        }

        var icon: String {
            switch self {
            case .inReview:
                return "clock.badge.checkmark"
            case .needsRecapture:
                return "arrow.clockwise.circle.fill"
            case .paid:
                return "banknote.fill"
            }
        }
    }

    enum HomeSectionKind: Equatable {
        case readyNearby
        case nearby
        case special
        case submissions
        case reviewSubmission
    }

    struct PreviewSelection: Equatable {
        let url: URL?
        let source: PreviewSource
    }

    struct JobItem: Identifiable, Equatable {
        let job: ScanJob
        let distanceMeters: Double
        let distanceMiles: Double
        let targetState: TargetState?
        let permissionTier: CapturePermissionTier
        let opportunityKind: CaptureOpportunityKind
        let previewURL: URL?
        let previewSource: PreviewSource

        var id: String { job.id }

        var isReadyNow: Bool {
            distanceMeters <= Double(job.checkinRadiusM)
        }

        var availabilityBadge: String? {
            guard let state = targetState else { return nil }
            switch state.status {
            case .reserved:
                return "Reserved"
            case .in_progress:
                return "Capturing"
            case .completed:
                return "Complete"
            case .available:
                return nil
            }
        }

        var payoutLabel: String {
            let cents = job.quotedPayoutCents ?? job.payoutCents
            let dollars = NSDecimalNumber(decimal: Decimal(cents) / Decimal(100))
            return NumberFormatter.captureCurrency.string(from: dollars) ?? "$\(job.payoutDollars)"
        }

        var distanceLabel: String {
            if isReadyNow {
                return "Here now"
            }
            return String(format: "%.1f mi", distanceMiles)
        }

        var reviewNote: String {
            switch permissionTier {
            case .approved:
                return "Commercial use cleared for the approved scope."
            case .reviewRequired:
                return "Starts as a reviewed submission before it becomes reusable."
            case .permissionRequired:
                return "Public-area capture may be possible, but be ready to stop if staff objects and avoid restricted zones."
            case .blocked:
                return "This location is restricted. Do not capture it."
            }
        }

        func withPreview(_ selection: PreviewSelection) -> JobItem {
            JobItem(
                job: job,
                distanceMeters: distanceMeters,
                distanceMiles: distanceMiles,
                targetState: targetState,
                permissionTier: permissionTier,
                opportunityKind: opportunityKind,
                previewURL: selection.url,
                previewSource: selection.source
            )
        }
    }

    struct SubmissionSummaryItem: Identifiable, Equatable {
        let stage: CaptureSubmissionStage
        let count: Int

        var id: String { stage.rawValue }
    }

    struct RankedJob: Equatable {
        let job: ScanJob
        let distanceMeters: Double
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var items: [JobItem] = []
    @Published private(set) var nearbyItems: [JobItem] = []
    @Published private(set) var specialItems: [JobItem] = []
    @Published private(set) var readyNow: JobItem?
    @Published private(set) var submissionSummary: [SubmissionSummaryItem] = []
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var lastUpdatedAt: Date?

    @Published var showErrorAlert: Bool = false
    @Published var errorMessage: String?

    private let jobsRepository: JobsRepositoryProtocol
    private let targetStateService: TargetStateServiceProtocol
    private let locationService: LocationServiceProtocol
    private let alertsManager: NearbyAlertsManager
    private let captureHistoryService: CaptureHistoryServiceProtocol
    private let demandIntelligenceService: DemandIntelligenceServiceProtocol
    private let nearbyDiscoveryService: NearbyCandidateDiscoveryServiceProtocol

    private let feedRadiusMeters: Double = 10.0 * 1609.34
    private let inferredNearbyLimit: Int = 8

    init(
        jobsRepository: JobsRepositoryProtocol = JobsRepository(),
        targetStateService: TargetStateServiceProtocol = TargetStateService(),
        locationService: LocationServiceProtocol = LocationService(),
        alertsManager: NearbyAlertsManager,
        captureHistoryService: CaptureHistoryServiceProtocol = APIService.shared,
        demandIntelligenceService: DemandIntelligenceServiceProtocol = APIService.shared,
        nearbyDiscoveryService: NearbyCandidateDiscoveryServiceProtocol = NearbyCandidateDiscoveryService()
    ) {
        self.jobsRepository = jobsRepository
        self.targetStateService = targetStateService
        self.locationService = locationService
        self.alertsManager = alertsManager
        self.captureHistoryService = captureHistoryService
        self.demandIntelligenceService = demandIntelligenceService
        self.nearbyDiscoveryService = nearbyDiscoveryService

        self.locationService.setListener { [weak self] loc in
            Task { @MainActor in
                self?.currentLocation = loc
                await self?.refresh()
            }
        }
    }

    func onAppear() {
        alertsManager.refreshNotificationStatus()
        locationService.requestWhenInUseAuthorization()
        locationService.startUpdatingLocation()
        if state == .idle {
            state = .loading
        }
    }

    func onDisappear() {
        locationService.stopUpdatingLocation()
    }

    func refresh() async {
        guard let loc = currentLocation else {
            state = .loading
            return
        }

        state = .loading

        do {
            _ = try await UserDeviceService.ensureFirebaseGuestSession(timeout: 10)
        } catch {
            let msg = Self.humanizedError(error)
            SessionEventManager.shared.logError(
                errorCode: "guest_auth_bootstrap_failed",
                metadata: [
                    "message": error.localizedDescription
                ]
            )
            state = .error(msg)
            errorMessage = msg
            showErrorAlert = true
            return
        }

        do {
            let jobs = try await fetchRankedJobs(userLocation: loc)
            let ranked = Self.rankJobsForFeed(jobs: jobs, userLocation: loc, feedRadiusMeters: feedRadiusMeters)
            let jobIds = ranked.map { $0.job.id }
            let states = await targetStateService.batchFetchStates(for: jobIds)

            let currentUserId = UserDeviceService.resolvedUserId()
            let visible = Self.filterVisibleItems(
                rankedJobs: ranked,
                statesByJobId: states,
                currentUserId: currentUserId
            )

            let hydrated = await hydrate(items: visible)
            self.items = hydrated
            let nearbyDynamic = hydrated.filter { $0.opportunityKind == .nearby }
            let openCaptureItem = RuntimeConfig.current.enableOpenCaptureHere
                ? await Self.makeCurrentLocationItem(at: loc)
                : nil
            self.nearbyItems = Self.nearbyItemsWithOpenCapture(
                nearbyDynamic: nearbyDynamic,
                openCaptureItem: openCaptureItem
            )
            self.specialItems = hydrated.filter { $0.opportunityKind == .special }
            self.readyNow = self.nearbyItems.first(where: { $0.isReadyNow && $0.permissionTier == .approved })
            self.submissionSummary = await loadSubmissionSummary()
            self.lastUpdatedAt = Date()
            self.state = .loaded

            let reservedIds = Set(hydrated.compactMap { item -> String? in
                guard let state = item.targetState else { return nil }
                if state.status == .reserved || state.status == .in_progress {
                    let owner = state.checkedInBy ?? state.reservedBy
                    if owner == currentUserId { return item.job.id }
                }
                return nil
            })

            alertsManager.scheduleNearbyAlerts(
                for: hydrated.map(\.job),
                userLocation: loc,
                maxRegions: 10,
                reservedJobIds: reservedIds
            )
        } catch {
            let msg = Self.humanizedError(error)
            state = .error(msg)
            errorMessage = msg
            showErrorAlert = true
        }
    }

    /// Translates low-level Firestore/network errors into actionable copy.
    private static func humanizedError(_ error: Error) -> String {
        if let bootstrapError = error as? UserDeviceService.GuestBootstrapError {
            return bootstrapError.errorDescription ?? "Blueprint could not start the guest capture session for this build."
        }
        let ns = error as NSError
        // Firestore permission denied (code 7 = PERMISSION_DENIED)
        if ns.domain == "FIRFirestoreErrorDomain" && ns.code == 7 {
            return "Blueprint could not load live captures for the guest session. Check Firebase Anonymous Auth and Firestore access for this build, then pull down to refresh."
        }
        // Firestore unavailable / no network (code 14 = UNAVAILABLE)
        if ns.domain == "FIRFirestoreErrorDomain" && ns.code == 14 {
            return "Can't reach the server. Check your connection and pull down to refresh."
        }
        // Generic network error
        if ns.domain == NSURLErrorDomain {
            return "Network error. Check your connection and pull down to refresh."
        }
        return error.localizedDescription
    }

    func nearbyPolicyCount(for tier: CapturePermissionTier) -> Int {
        nearbyItems.filter { $0.permissionTier == tier }.count
    }

    nonisolated static func nearbyItemsWithOpenCapture(
        nearbyDynamic: [JobItem],
        openCaptureItem: JobItem?
    ) -> [JobItem] {
        guard let openCaptureItem else { return nearbyDynamic }
        let filtered = nearbyDynamic.filter { $0.id != alphaCurrentLocationJobID }
        return [openCaptureItem] + filtered
    }

    private func hydrate(items: [JobItem]) async -> [JobItem] {
        var hydrated: [JobItem] = []
        hydrated.reserveCapacity(items.count)

        for (index, item) in items.enumerated() {
            if index < 12 {
                let preview = await previewSelection(for: item.job)
                hydrated.append(item.withPreview(preview))
            } else {
                hydrated.append(item.withPreview(Self.previewSelection(for: item.job)))
            }
        }

        return hydrated
    }

    private func previewSelection(for job: ScanJob) async -> PreviewSelection {
        if let explicit = job.primaryImageURL {
            return PreviewSelection(url: explicit, source: .jobImage)
        }

        return PreviewSelection(url: nil, source: .mapSnapshot)
    }

    private func loadSubmissionSummary() async -> [SubmissionSummaryItem] {
        guard let history = try? await captureHistoryService.fetchCaptureHistory() else {
            return CaptureSubmissionStage.allCases.map { SubmissionSummaryItem(stage: $0, count: 0) }
        }

        let grouped = Dictionary(grouping: history) { Self.submissionStage(for: $0.status) }
        return CaptureSubmissionStage.allCases.map { stage in
            SubmissionSummaryItem(stage: stage, count: grouped[stage]?.count ?? 0)
        }
    }

    // MARK: - Open Capture Here

    /// An explicit open-capture flow pinned to the user's current GPS position.
    /// This stays visually distinct from approved marketplace jobs and requires
    /// an explicit rights acknowledgement before recording starts.
    nonisolated static let alphaCurrentLocationJobID = "alpha-current-location"

    private static func makeCurrentLocationItem(at location: CLLocation) async -> JobItem {
        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude

        // Reverse-geocode to show a real street address instead of raw coordinates.
        let address: String
        if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
            let parts = [
                placemark.subThoroughfare,
                placemark.thoroughfare,
                placemark.locality
            ].compactMap { $0 }
            address = parts.isEmpty
                ? String(format: "%.5f, %.5f", lat, lng)
                : parts.joined(separator: " ")
        } else {
            address = String(format: "%.5f, %.5f", lat, lng)
        }

        let job = ScanJob(
            id: alphaCurrentLocationJobID,
            title: "Open Capture Here",
            address: address,
            lat: lat,
            lng: lng,
            payoutCents: 0,
            estMinutes: 20,
            active: true,
            updatedAt: Date(),
            thumbnailURL: nil,
            heroImageURL: nil,
            category: "OPEN CAPTURE",
            instructions: [
                "Confirm you have permission to capture and commercialize this space before you start.",
                "Capture the full accessible area around you.",
                "Pause 2-3 seconds at each major transition point.",
                "Capture from multiple heights where possible."
            ],
            allowedAreas: ["All visible areas"],
            restrictedAreas: ["Do not capture restricted, private, or unapproved areas."],
            permissionDocURL: nil,
            checkinRadiusM: 999_999,
            alertRadiusM: 999_999,
            priority: 100,
            priorityWeight: 100.0,
            regionId: nil,
            jobType: .operatorApprovedOnDemand,
            buyerRequestId: nil,
            siteSubmissionId: nil,
            quotedPayoutCents: nil,
            dueWindow: nil,
            approvalRequirements: [],
            recaptureReason: nil,
            rightsChecklist: [
                "I have permission to capture this space.",
                "I will avoid restricted or private areas.",
                "I understand qualification, privacy, and rights checks can block downstream use.",
            ],
            rightsProfile: nil,
            requestedOutputs: ["qualification", "preview_simulation", "deeper_evaluation"],
            workflowName: "Open Capture Here",
            workflowSteps: [
                "Confirm rights and consent for this capture.",
                "Capture the full accessible area around you.",
                "Pause 2-3 seconds at each major transition point.",
                "Capture from multiple heights where possible."
            ],
            targetKPI: nil,
            zone: nil,
            shift: nil,
            owner: "open-capture",
            facilityTemplate: "general",
            benchmarkStations: [],
            lightingWindows: [],
            movableObstacles: [],
            floorConditionNotes: [],
            reflectiveSurfaceNotes: [],
            accessRules: [],
            adjacentSystems: [],
            privacyRestrictions: [],
            securityRestrictions: [],
            knownBlockers: [],
            nonRoutineModes: [],
            peopleTrafficNotes: [],
            captureRestrictions: []
        )
        return JobItem(
            job: job,
            distanceMeters: 0,
            distanceMiles: 0,
            targetState: nil,
            permissionTier: .reviewRequired,
            opportunityKind: .nearby,
            previewURL: nil,
            previewSource: .mapSnapshot
        )
    }

    private func fetchRankedJobs(userLocation: CLLocation) async throws -> [ScanJob] {
        let candidatePlaces = await loadNearbyCandidatePlaces(userLocation: userLocation)

        guard AppConfig.hasDemandBackendBaseURL() else {
            let curated = try await jobsRepository.fetchActiveJobs(limit: 200)
            guard !candidatePlaces.isEmpty else { return curated }
            return Self.mergeCuratedAndInferredJobs(
                curated,
                inferred: candidatePlaces.map { Self.makeInferredNearbyJob(from: $0) }
            )
        }

        let request = DemandOpportunityFeedRequest(
            lat: userLocation.coordinate.latitude,
            lng: userLocation.coordinate.longitude,
            radiusMeters: Int(feedRadiusMeters.rounded()),
            limit: 200,
            candidatePlaces: candidatePlaces.map {
                OpportunityCandidatePlace(
                    placeId: $0.placeId,
                    displayName: $0.displayName,
                    formattedAddress: $0.formattedAddress,
                    lat: $0.lat,
                    lng: $0.lng,
                    placeTypes: $0.types ?? []
                )
            }
        )

        do {
            let response = try await demandIntelligenceService.fetchDemandOpportunityFeed(request)
            let merged = Self.mergeCuratedAndInferredJobs(
                response.captureJobs,
                inferred: response.nearbyOpportunities.map(Self.makeInferredNearbyJob(from:))
            )
            if !merged.isEmpty {
                return merged
            }
        } catch {
            SessionEventManager.shared.logError(
                errorCode: "demand_ranking_failed",
                metadata: [
                    "message": error.localizedDescription
                ]
            )
            print("⚠️ [ScanHome] Demand opportunity feed failed, falling back to Firestore jobs: \(error.localizedDescription)")
        }

        let curated = try await jobsRepository.fetchActiveJobs(limit: 200)
        guard !candidatePlaces.isEmpty else { return curated }
        return Self.mergeCuratedAndInferredJobs(
            curated,
            inferred: candidatePlaces.map { Self.makeInferredNearbyJob(from: $0) }
        )
    }

    private func loadNearbyCandidatePlaces(userLocation: CLLocation) async -> [PlaceDetailsLite] {
        guard RuntimeConfig.current.availability(for: .nearbyDiscovery).isEnabled else {
            return []
        }

        do {
            return try await nearbyDiscoveryService.discoverCandidatePlaces(
                userLocation: userLocation.coordinate,
                radiusMeters: Int(feedRadiusMeters.rounded()),
                limit: inferredNearbyLimit,
                includedTypes: Self.inferredNearbyIncludedTypes
            )
        } catch {
            print("⚠️ [ScanHome] Nearby candidate discovery failed: \(error.localizedDescription)")
            return []
        }
    }
}

extension ScanHomeViewModel {
    static let inferredNearbyIncludedTypes: [String] = [
        "supermarket",
        "electronics_store",
        "shopping_mall",
        "department_store",
        "warehouse_store",
        "hardware_store",
        "home_improvement_store",
        "home_goods_store",
        "furniture_store",
        "store",
        "convenience_store",
        "pharmacy",
        "clothing_store"
    ]

    static func rankJobsForFeed(jobs: [ScanJob], userLocation: CLLocation, feedRadiusMeters: Double) -> [RankedJob] {
        let nearby = jobs
            .filter { $0.active }
            .map { job in RankedJob(job: job, distanceMeters: job.distanceMeters(from: userLocation)) }
            .filter { $0.distanceMeters <= feedRadiusMeters }

        return nearby.sorted { lhs, rhs in
            let lhsReady = lhs.distanceMeters <= Double(lhs.job.checkinRadiusM)
            let rhsReady = rhs.distanceMeters <= Double(rhs.job.checkinRadiusM)
            if lhsReady != rhsReady { return lhsReady && !rhsReady }

            let lhsSpecial = captureOpportunityKind(for: lhs.job) == .special
            let rhsSpecial = captureOpportunityKind(for: rhs.job) == .special
            if lhsSpecial != rhsSpecial { return lhsSpecial && !rhsSpecial }

            let lhsOpportunity = lhs.job.opportunityScore ?? lhs.job.demandScore ?? -1
            let rhsOpportunity = rhs.job.opportunityScore ?? rhs.job.demandScore ?? -1
            if lhsOpportunity != rhsOpportunity { return lhsOpportunity > rhsOpportunity }

            if lhs.job.priority != rhs.job.priority { return lhs.job.priority > rhs.job.priority }
            if lhs.job.payoutCents != rhs.job.payoutCents { return lhs.job.payoutCents > rhs.job.payoutCents }
            if lhs.distanceMeters != rhs.distanceMeters { return lhs.distanceMeters < rhs.distanceMeters }
            return lhs.job.id < rhs.job.id
        }
    }

    static func filterVisibleItems(
        rankedJobs: [RankedJob],
        statesByJobId: [String: TargetState],
        currentUserId: String
    ) -> [JobItem] {
        rankedJobs.compactMap { ranked in
            let job = ranked.job
            let state = statesByJobId[job.id]

            if let state {
                switch state.status {
                case .completed:
                    return nil
                case .reserved, .in_progress:
                    let owner = state.checkedInBy ?? state.reservedBy
                    if owner == nil || owner != currentUserId { return nil }
                case .available:
                    break
                }
            }

            let miles = ranked.distanceMeters / 1609.34
            return JobItem(
                job: job,
                distanceMeters: ranked.distanceMeters,
                distanceMiles: miles,
                targetState: state,
                permissionTier: permissionTier(for: job),
                opportunityKind: captureOpportunityKind(for: job),
                previewURL: nil,
                previewSource: .mapSnapshot
            )
        }
    }

    static func permissionTier(for job: ScanJob) -> CapturePermissionTier {
        let restrictionText = (job.captureRestrictions + job.restrictedAreas + job.approvalRequirements + job.rightsChecklist)
            .joined(separator: " ")
            .lowercased()
        let rightsProfile = job.rightsProfile?.lowercased() ?? ""

        let blockedKeywords = ["no capture", "not allowed", "prohibited", "never allowed", "strictly prohibited", "blocked"]
        if blockedKeywords.contains(where: { restrictionText.contains($0) }) || rightsProfile == "blocked" {
            return .blocked
        }

        if job.permissionDocURL != nil || rightsProfile == "documented_permission" || job.captureConsentStatus == .documented {
            return .approved
        }

        if job.jobType == .operatorApprovedOnDemand || rightsProfile == "review_required" || rightsProfile == "review_only" {
            return .reviewRequired
        }

        if rightsProfile == "policy_only" || !job.allowedAreas.isEmpty || !job.restrictedAreas.isEmpty || !job.rightsChecklist.isEmpty {
            return .permissionRequired
        }

        return .reviewRequired
    }

    static func captureOpportunityKind(for job: ScanJob) -> CaptureOpportunityKind {
        switch job.jobType {
        case .buyerRequestedSpecialTask:
            return .special
        case .curatedNearby, .operatorApprovedOnDemand:
            return .nearby
        }
    }

    static func previewSelection(for job: ScanJob) -> PreviewSelection {
        if let explicit = job.primaryImageURL {
            return PreviewSelection(url: explicit, source: .jobImage)
        }
        return PreviewSelection(url: nil, source: .mapSnapshot)
    }

    static func submissionStage(for status: CaptureStatus) -> CaptureSubmissionStage {
        switch status {
        case .needsRecapture, .needsFix, .rejected:
            return .needsRecapture
        case .paid:
            return .paid
        case .draft, .readyToSubmit, .submitted, .underReview, .processing, .qc, .approved:
            return .inReview
        }
    }

    static func mergeCuratedAndInferredJobs(_ curated: [ScanJob], inferred: [ScanJob]) -> [ScanJob] {
        guard !inferred.isEmpty else { return curated }
        var merged = curated
        for candidate in inferred where !curated.contains(where: { inferredJob($0, matches: candidate) }) {
            merged.append(candidate)
        }
        return merged
    }

    static func makeInferredNearbyJob(from opportunity: RankedNearbyOpportunity) -> ScanJob {
        makeInferredNearbyJob(
            placeId: opportunity.placeId,
            displayName: opportunity.displayName,
            formattedAddress: opportunity.formattedAddress,
            lat: opportunity.lat,
            lng: opportunity.lng,
            placeTypes: opportunity.placeTypes,
            siteType: opportunity.siteType,
            demandScore: opportunity.demandScore,
            opportunityScore: opportunity.opportunityScore,
            demandSummary: opportunity.demandSummary,
            rankingExplanation: opportunity.rankingExplanation,
            suggestedWorkflows: opportunity.suggestedWorkflows,
            demandSourceKinds: opportunity.demandSourceKinds.map(\.rawValue)
        )
    }

    static func makeInferredNearbyJob(from place: PlaceDetailsLite) -> ScanJob {
        let inferredScore = inferredNearbyDemandScore(for: place.types ?? [])
        return makeInferredNearbyJob(
            placeId: place.placeId,
            displayName: place.displayName,
            formattedAddress: place.formattedAddress,
            lat: place.lat,
            lng: place.lng,
            placeTypes: place.types ?? [],
            siteType: nil,
            demandScore: inferredScore,
            opportunityScore: inferredScore,
            demandSummary: "Inferred nearby candidate sourced from live place search.",
            rankingExplanation: "Nearby place candidate that still requires Blueprint review before it becomes an approved capture job.",
            suggestedWorkflows: []
        )
    }

    static func inferredNearbyDemandScore(for types: [String]) -> Double {
        let normalized = Set(types.map { $0.lowercased() })
        let table: [String: Double] = [
            "warehouse_store": 0.9,
            "hardware_store": 0.82,
            "home_improvement_store": 0.84,
            "department_store": 0.78,
            "shopping_mall": 0.76,
            "supermarket": 0.74,
            "electronics_store": 0.8,
            "furniture_store": 0.72,
            "home_goods_store": 0.7,
            "store": 0.65,
            "clothing_store": 0.6,
            "convenience_store": 0.58,
            "pharmacy": 0.55
        ]
        return normalized.compactMap { table[$0] }.max() ?? 0.55
    }

    private static func inferredJob(_ lhs: ScanJob, matches rhs: ScanJob) -> Bool {
        let lhsAddress = lhs.address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rhsAddress = rhs.address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !lhsAddress.isEmpty, lhsAddress == rhsAddress {
            return true
        }
        let lhsLocation = CLLocation(latitude: lhs.lat, longitude: lhs.lng)
        let rhsLocation = CLLocation(latitude: rhs.lat, longitude: rhs.lng)
        return lhsLocation.distance(from: rhsLocation) <= 75
    }

    private static func inferredNearbyProfile(for types: [String], siteType: String?, demandScore: Double) -> (categoryLabel: String, payoutCents: Int, estimatedMinutes: Int) {
        let normalized = Set((types + [siteType].compactMap { $0 }).map { $0.lowercased() })
        let base: (String, Int, Int) = {
            if normalized.contains("warehouse_store") || normalized.contains("warehouse") || normalized.contains("distribution_center") {
                return ("Warehouse Candidate", 7000, 35)
            }
            if normalized.contains("factory") || normalized.contains("manufacturing") || normalized.contains("industrial") {
                return ("Factory Candidate", 7500, 40)
            }
            if normalized.contains("department_store") || normalized.contains("shopping_mall") || normalized.contains("supermarket") || normalized.contains("store") {
                return ("Retail Candidate", 4000, 25)
            }
            if normalized.contains("hardware_store") || normalized.contains("home_improvement_store") {
                return ("Industrial Retail Candidate", 5200, 30)
            }
            return ("Inferred Candidate", 3200, 20)
        }()
        let multiplier: Double = demandScore >= 0.8 ? 1.2 : (demandScore >= 0.65 ? 1.1 : 1.0)
        return (base.0, Int((Double(base.1) * multiplier).rounded()), base.2)
    }

    private static func makeInferredNearbyJob(
        placeId: String,
        displayName: String,
        formattedAddress: String?,
        lat: Double,
        lng: Double,
        placeTypes: [String],
        siteType: String?,
        demandScore: Double,
        opportunityScore: Double,
        demandSummary: String?,
        rankingExplanation: String?,
        suggestedWorkflows: [String],
        demandSourceKinds: [String] = ["inferred_signal"]
    ) -> ScanJob {
        let profile = inferredNearbyProfile(for: placeTypes, siteType: siteType, demandScore: demandScore)
        let workflowSteps = suggestedWorkflows.isEmpty
            ? [
                "Treat this as an inferred nearby candidate, not an approved capture job.",
                "Capture only publicly accessible or clearly permitted common areas.",
                "Stop immediately if signage, staff, or site conditions indicate capture is not allowed."
            ]
            : suggestedWorkflows
        return ScanJob(
            id: "poi-\(placeId)",
            title: displayName,
            address: formattedAddress ?? displayName,
            lat: lat,
            lng: lng,
            payoutCents: profile.payoutCents,
            estMinutes: profile.estimatedMinutes,
            active: true,
            updatedAt: Date(),
            thumbnailURL: nil,
            heroImageURL: nil,
            category: profile.categoryLabel,
            instructions: workflowSteps,
            allowedAreas: [],
            restrictedAreas: [],
            permissionDocURL: nil,
            checkinRadiusM: 150,
            alertRadiusM: 200,
            priority: 0,
            priorityWeight: 0.5,
            regionId: nil,
            jobType: .operatorApprovedOnDemand,
            buyerRequestId: nil,
            siteSubmissionId: nil,
            quotedPayoutCents: profile.payoutCents,
            dueWindow: nil,
            approvalRequirements: ["blueprint_review"],
            recaptureReason: nil,
            rightsChecklist: ["Treat as inferred nearby candidate until Blueprint review completes"],
            rightsProfile: "review_required",
            requestedOutputs: ["qualification", "review_intake"],
            workflowName: suggestedWorkflows.first ?? "Inferred nearby candidate review",
            workflowSteps: workflowSteps,
            targetKPI: nil,
            zone: nil,
            shift: nil,
            owner: nil,
            facilityTemplate: nil,
            benchmarkStations: [],
            lightingWindows: [],
            movableObstacles: [],
            floorConditionNotes: [],
            reflectiveSurfaceNotes: [],
            accessRules: [],
            adjacentSystems: [],
            privacyRestrictions: [],
            securityRestrictions: [],
            knownBlockers: [],
            nonRoutineModes: [],
            peopleTrafficNotes: [],
            captureRestrictions: [],
            siteType: siteType,
            demandScore: demandScore,
            opportunityScore: opportunityScore,
            demandSummary: demandSummary,
            rankingExplanation: rankingExplanation,
            demandSourceKinds: demandSourceKinds,
            suggestedWorkflows: suggestedWorkflows
        )
    }

    static func homeSectionKinds(
        hasReadyNearby: Bool,
        nearbyCount: Int,
        specialCount: Int,
        submissionCount: Int
    ) -> [HomeSectionKind] {
        var sections: [HomeSectionKind] = []
        if hasReadyNearby {
            sections.append(.readyNearby)
        }
        if nearbyCount > 0 {
            sections.append(.nearby)
        }
        if specialCount > 0 {
            sections.append(.special)
        }
        if submissionCount > 0 {
            sections.append(.submissions)
        }
        sections.append(.reviewSubmission)
        return sections
    }
}

private extension NumberFormatter {
    static let captureCurrency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        formatter.currencyCode = "USD"
        return formatter
    }()
}
