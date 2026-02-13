import Foundation
import Combine
import CoreLocation

@MainActor
final class ScanHomeViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    struct JobItem: Identifiable, Equatable {
        let job: ScanJob
        let distanceMeters: Double
        let distanceMiles: Double
        let targetState: TargetState?

        var id: String { job.id }

        var isReadyNow: Bool {
            distanceMeters <= Double(job.checkinRadiusM)
        }

        var statusBadge: String? {
            guard let state = targetState else { return nil }
            switch state.status {
            case .reserved:
                return "Reserved"
            case .in_progress:
                return "In progress"
            case .completed:
                return "Completed"
            case .available:
                return nil
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var items: [JobItem] = []
    @Published private(set) var readyNow: JobItem?
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var lastUpdatedAt: Date?

    @Published var showErrorAlert: Bool = false
    @Published var errorMessage: String?

    private let jobsRepository: JobsRepositoryProtocol
    private let targetStateService: TargetStateServiceProtocol
    private let locationService: LocationServiceProtocol
    private let alertsManager: NearbyAlertsManager

    private let feedRadiusMeters: Double = 10.0 * 1609.34

    init(jobsRepository: JobsRepositoryProtocol = JobsRepository(),
         targetStateService: TargetStateServiceProtocol = TargetStateService(),
         locationService: LocationServiceProtocol = LocationService(),
         alertsManager: NearbyAlertsManager) {
        self.jobsRepository = jobsRepository
        self.targetStateService = targetStateService
        self.locationService = locationService
        self.alertsManager = alertsManager

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

            self.items = visible
            self.readyNow = visible.first(where: { $0.isReadyNow })
            self.lastUpdatedAt = Date()
            self.state = .loaded

            // Proximity alerts: schedule off the visible feed ordering.
            let reservedIds = Set(visible.compactMap { item -> String? in
                guard let s = item.targetState else { return nil }
                if s.status == .reserved || s.status == .in_progress {
                    let owner = s.checkedInBy ?? s.reservedBy
                    if owner == currentUserId { return item.job.id }
                }
                return nil
            })
            alertsManager.scheduleNearbyAlerts(
                for: visible.map { $0.job },
                userLocation: loc,
                maxRegions: 10,
                reservedJobIds: reservedIds
            )
        } catch {
            state = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }
}

extension ScanHomeViewModel {
    struct RankedJob: Equatable {
        let job: ScanJob
        let distanceMeters: Double
    }

    nonisolated static func rankJobsForFeed(jobs: [ScanJob], userLocation: CLLocation, feedRadiusMeters: Double) -> [RankedJob] {
        let nearby = jobs
            .filter { $0.active }
            .map { job in RankedJob(job: job, distanceMeters: job.distanceMeters(from: userLocation)) }
            .filter { $0.distanceMeters <= feedRadiusMeters }

        return nearby.sorted { lhs, rhs in
            // 1) ready-now first
            let lhsReady = lhs.distanceMeters <= Double(lhs.job.checkinRadiusM)
            let rhsReady = rhs.distanceMeters <= Double(rhs.job.checkinRadiusM)
            if lhsReady != rhsReady { return lhsReady && !rhsReady }

            // 2) higher priority first
            if lhs.job.priority != rhs.job.priority { return lhs.job.priority > rhs.job.priority }

            // 3) higher payout first
            if lhs.job.payoutCents != rhs.job.payoutCents { return lhs.job.payoutCents > rhs.job.payoutCents }

            // 4) nearer first
            if lhs.distanceMeters != rhs.distanceMeters { return lhs.distanceMeters < rhs.distanceMeters }
            return lhs.job.id < rhs.job.id
        }
    }

    nonisolated static func filterVisibleItems(rankedJobs: [RankedJob], statesByJobId: [String: TargetState], currentUserId: String) -> [JobItem] {
        rankedJobs.compactMap { ranked in
            let job = ranked.job
            let s = statesByJobId[job.id]

            // Gating rules
            if let s {
                switch s.status {
                case .completed:
                    return nil
                case .reserved, .in_progress:
                    let owner = s.checkedInBy ?? s.reservedBy
                    if owner == nil { return nil }
                    if owner != currentUserId { return nil }
                case .available:
                    break
                }
            }

            let miles = ranked.distanceMeters / 1609.34
            return JobItem(job: job, distanceMeters: ranked.distanceMeters, distanceMiles: miles, targetState: s)
        }
    }
}
