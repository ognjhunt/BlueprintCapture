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

    private let feedRadiusMeters: Double = 10.0 * 1609.34

    init(
        jobsRepository: JobsRepositoryProtocol = JobsRepository(),
        targetStateService: TargetStateServiceProtocol = TargetStateService(),
        locationService: LocationServiceProtocol = LocationService(),
        alertsManager: NearbyAlertsManager,
        captureHistoryService: CaptureHistoryServiceProtocol = APIService.shared
    ) {
        self.jobsRepository = jobsRepository
        self.targetStateService = targetStateService
        self.locationService = locationService
        self.alertsManager = alertsManager
        self.captureHistoryService = captureHistoryService

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
            let jobs = try await jobsRepository.fetchActiveJobs(limit: 200)
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
            // Always prepend the hardcoded alpha test space (current location) so the
            // full non-GPU pipeline can be exercised against a real capture from this device.
            self.nearbyItems = [Self.makeCurrentLocationItem(at: loc)] + nearbyDynamic
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
        let ns = error as NSError
        // Firestore permission denied (code 7 = PERMISSION_DENIED)
        if ns.domain == "FIRFirestoreErrorDomain" && ns.code == 7 {
            return "Sign-in required to load captures. Finish setting up your account in the Profile tab, then pull down to refresh."
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

    // MARK: - Alpha Internal Test Space

    /// A hardcoded capture opportunity pinned to the user's current GPS position.
    /// Always `.approved` so it bypasses all permission gates and lets the full
    /// non-GPU pipeline run against a live device capture for internal testing.
    static let alphaCurrentLocationJobID = "alpha-current-location"

    private static func makeCurrentLocationItem(at location: CLLocation) -> JobItem {
        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude
        let job = ScanJob(
            id: alphaCurrentLocationJobID,
            title: "Current Location",
            address: String(format: "%.5f, %.5f", lat, lng),
            lat: lat,
            lng: lng,
            payoutCents: 4500,
            estMinutes: 20,
            active: true,
            updatedAt: Date(),
            thumbnailURL: nil,
            heroImageURL: nil,
            category: "ALPHA",
            instructions: [
                "Capture the full space you are currently in.",
                "Walk through every accessible room or area.",
                "Pause 2-3 seconds at each major transition point.",
                "Capture from multiple heights where possible."
            ],
            allowedAreas: ["All visible areas"],
            restrictedAreas: [],
            permissionDocURL: nil,
            checkinRadiusM: 999_999,
            alertRadiusM: 999_999,
            priority: 100,
            priorityWeight: 100.0,
            regionId: nil,
            jobType: .operatorApprovedOnDemand,
            buyerRequestId: nil,
            siteSubmissionId: nil,
            quotedPayoutCents: 4500,
            dueWindow: nil,
            approvalRequirements: [],
            recaptureReason: nil,
            rightsChecklist: [],
            rightsProfile: nil,
            requestedOutputs: ["qualification", "preview_simulation", "deeper_evaluation"],
            workflowName: "Alpha Internal Test Capture",
            workflowSteps: [
                "Capture the full space you are currently in.",
                "Walk through every accessible room or area.",
                "Pause 2-3 seconds at each major transition point.",
                "Capture from multiple heights where possible."
            ],
            targetKPI: nil,
            zone: nil,
            shift: nil,
            owner: "blueprint-internal",
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
            permissionTier: .approved,
            opportunityKind: .nearby,
            previewURL: nil,
            previewSource: .mapSnapshot
        )
    }
}

extension ScanHomeViewModel {
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
