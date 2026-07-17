import Foundation
import Combine
import CoreLocation

// MARK: - OnboardingNearbyPreviewViewModel
//
// Powers the pre-auth "what's around you" onboarding step. Read-only by design:
// published capture jobs load through the guest Firestore session when available,
// and candidate places come from the same provider-selected discovery service the
// home feed uses (no review submissions, nothing reserved, no writes before the
// capturer registers). Payout labels are stricter than the signed-in feed: this
// public surface shows a payout ONLY when the job carries a real backend quote
// (`quotedPayoutCents`) — legacy `payoutCents` alone never becomes a pre-auth
// payout claim.

@MainActor
final class OnboardingNearbyPreviewViewModel: ObservableObject {

    enum Phase: Equatable {
        /// Location permission has not been requested yet — show the primer.
        case primer
        /// Waiting on the OS prompt or the first location fix.
        case locating
        case loading
        case loaded
        /// Location denied/restricted — preview unavailable, onboarding continues.
        case denied
        /// Loaded successfully but nothing mapped within the radius.
        case empty
    }

    struct PreviewItem: Identifiable, Equatable {
        let id: String
        let title: String
        let detail: String
        let distanceLabel: String
        /// Formatted quoted payout. Nil unless the job carries a real quote — the
        /// row shows the review-gated placeholder instead of a fabricated number.
        let payoutLabel: String?
        /// Nil for walk-in candidate places that are not published jobs.
        let tier: ScanHomeViewModel.CapturePermissionTier?

        var isCandidate: Bool { tier == nil }
    }

    @Published private(set) var phase: Phase = .primer
    @Published private(set) var previewItems: [PreviewItem] = []
    @Published var searchText: String = ""

    private let locationService: LocationServiceProtocol
    private let jobsRepository: JobsRepositoryProtocol
    private let nearbyDiscovery: NearbyCandidateDiscoveryServiceProtocol
    private let funnel: ActivationFunnelRecording

    private let feedRadiusMeters: Double = 10.0 * 1609.34
    private var permissionStepRecorded = false
    private var permissionOutcomeRecorded = false
    private var hasLoaded = false

    init(
        locationService: LocationServiceProtocol = LocationService(),
        jobsRepository: JobsRepositoryProtocol = JobsRepository(),
        nearbyDiscovery: NearbyCandidateDiscoveryServiceProtocol = NearbyCandidateDiscoveryService(),
        funnel: ActivationFunnelRecording = ActivationFunnelStore.shared
    ) {
        self.locationService = locationService
        self.jobsRepository = jobsRepository
        self.nearbyDiscovery = nearbyDiscovery
        self.funnel = funnel

        self.locationService.setListener { [weak self] location in
            Task { @MainActor in
                self?.handleLocationUpdate(location)
            }
        }
    }

    var filteredItems: [PreviewItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return previewItems }
        return previewItems.filter {
            $0.title.lowercased().contains(query) || $0.detail.lowercased().contains(query)
        }
    }

    var quotedJobCount: Int {
        previewItems.filter { $0.payoutLabel != nil }.count
    }

    /// Called when the preview step appears. Records the funnel's
    /// permissions-step-viewed event on every path (including permission already
    /// granted) so `permissions_granted_or_blocked` never appears without it; if
    /// access was granted earlier the primer is skipped and the preview loads
    /// immediately.
    func onStepAppear() {
        recordPermissionStepViewed()
        switch locationService.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            recordPermissionOutcome("granted")
            startLocating()
        case .denied, .restricted:
            recordPermissionOutcome("denied")
            if phase == .primer { phase = .denied }
        default:
            break
        }
    }

    /// Called when the preview step disappears — GPS never outlives the screen.
    func onStepDisappear() {
        locationService.stopUpdatingLocation()
    }

    func requestLocationAccess() {
        recordPermissionStepViewed()
        switch locationService.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            recordPermissionOutcome("granted")
            startLocating()
        case .denied, .restricted:
            recordPermissionOutcome("denied")
            phase = .denied
        default:
            phase = .locating
            locationService.requestWhenInUseAuthorization()
        }
    }

    private func startLocating() {
        guard !hasLoaded else { return }
        if phase == .primer || phase == .denied {
            phase = .locating
        }
        locationService.startUpdatingLocation()
        locationService.requestCurrentLocation()
        if let location = locationService.latestLocation {
            beginLoad(at: location)
        }
    }

    private func handleLocationUpdate(_ location: CLLocation?) {
        switch locationService.authorizationStatus {
        case .denied, .restricted:
            recordPermissionOutcome("denied")
            if !hasLoaded { phase = .denied }
        case .authorizedWhenInUse, .authorizedAlways:
            recordPermissionOutcome("granted")
            if let location {
                beginLoad(at: location)
            } else if phase == .primer {
                phase = .locating
            }
        default:
            break
        }
    }

    private func beginLoad(at location: CLLocation) {
        guard !hasLoaded else { return }
        hasLoaded = true
        // One fix is all the snapshot needs — stop the stream immediately.
        locationService.stopUpdatingLocation()
        phase = .loading
        Task { await load(at: location) }
    }

    private func recordPermissionStepViewed() {
        guard !permissionStepRecorded else { return }
        permissionStepRecorded = true
        funnel.record(
            .permissionsStepViewed,
            captureId: nil,
            metadata: ["reason": "onboarding_location_primer"]
        )
    }

    private func recordPermissionOutcome(_ outcome: String) {
        guard !permissionOutcomeRecorded else { return }
        permissionOutcomeRecorded = true
        funnel.record(
            .permissionsGrantedOrBlocked,
            captureId: nil,
            metadata: ["location": outcome, "reason": "onboarding_preview"]
        )
    }

    private func load(at location: CLLocation) async {
        // Ensure the guest session once up front: the jobs read and the backed
        // discovery providers both ride it. Failure is non-fatal — discovery
        // providers that need no session (MapKit) can still return candidates.
        let hasGuestSession: Bool
        do {
            _ = try await UserDeviceService.ensureFirebaseGuestSession(timeout: 8)
            hasGuestSession = true
        } catch {
            hasGuestSession = false
        }

        async let jobsFetch = fetchJobs(hasGuestSession: hasGuestSession)
        async let placesFetch = fetchCandidatePlaces(at: location)
        let (jobs, places) = await (jobsFetch, placesFetch)

        let items = Self.buildPreviewItems(
            jobs: jobs,
            candidatePlaces: places,
            userLocation: location,
            feedRadiusMeters: feedRadiusMeters
        )
        previewItems = items
        phase = items.isEmpty ? .empty : .loaded
    }

    private func fetchJobs(hasGuestSession: Bool) async -> [ScanJob] {
        guard hasGuestSession else { return [] }
        return (try? await jobsRepository.fetchActiveJobs(limit: 200)) ?? []
    }

    private func fetchCandidatePlaces(at location: CLLocation) async -> [PlaceDetailsLite] {
        guard RuntimeConfig.current.availability(for: .nearbyDiscovery).isEnabled else { return [] }
        return (try? await nearbyDiscovery.discoverCandidatePlaces(
            userLocation: location.coordinate,
            radiusMeters: Int(feedRadiusMeters.rounded()),
            limit: 12,
            includedTypes: ScanHomeViewModel.inferredNearbyIncludedTypes
        )) ?? []
    }

    // MARK: - Preview assembly

    /// Merges published jobs and walk-in candidate places into the read-only
    /// preview list. Published jobs keep the home feed's ranking and permission
    /// tiers; candidate places carry no payout and no tier. Blocked jobs never
    /// appear in a first-run pitch.
    static func buildPreviewItems(
        jobs: [ScanJob],
        candidatePlaces: [PlaceDetailsLite],
        userLocation: CLLocation,
        feedRadiusMeters: Double,
        maxJobs: Int = 10,
        maxCandidates: Int = 8
    ) -> [PreviewItem] {
        let ranked = ScanHomeViewModel.rankJobsForFeed(
            jobs: jobs,
            userLocation: userLocation,
            feedRadiusMeters: feedRadiusMeters
        )
        let visible = ScanHomeViewModel.filterVisibleItems(
            rankedJobs: ranked,
            statesByJobId: [:],
            currentUserId: "onboarding-preview"
        )

        let jobItems: [PreviewItem] = visible
            .filter { $0.permissionTier != .blocked }
            .prefix(maxJobs)
            .map { item in
                PreviewItem(
                    id: "job-\(item.id)",
                    title: item.job.title,
                    detail: item.job.category ?? item.job.address,
                    distanceLabel: item.distanceLabel,
                    payoutLabel: quotedPayoutLabel(for: item.job),
                    tier: item.permissionTier
                )
            }

        let seenNames = Set(jobItems.map { MapKitNearbyDiscoveryTransform.normalizedName($0.title) })
        let candidateItems: [PreviewItem] = candidatePlaces
            .map { place in
                (place, CLLocation(latitude: place.lat, longitude: place.lng).distance(from: userLocation))
            }
            .filter { $0.1 <= feedRadiusMeters }
            .filter {
                let name = MapKitNearbyDiscoveryTransform.normalizedName($0.0.displayName)
                return !name.isEmpty && !seenNames.contains(name)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(maxCandidates)
            .map { place, distanceMeters in
                PreviewItem(
                    id: "place-\(place.placeId)",
                    title: place.displayName,
                    detail: place.formattedAddress ?? "Nearby space",
                    distanceLabel: String(format: "%.1f mi", distanceMeters / 1609.34),
                    payoutLabel: nil,
                    tier: nil
                )
            }

        return jobItems + candidateItems
    }

    /// Pre-auth payout labels come ONLY from a real backend quote. The signed-in
    /// feed may fall back to legacy `payoutCents`, but this public surface must
    /// not advertise an unquoted amount (capturer copy positioning, 2026-05-13).
    /// Formatting matches the home feed's `NumberFormatter.captureCurrency`.
    static func quotedPayoutLabel(for job: ScanJob) -> String? {
        guard let cents = job.quotedPayoutCents, cents > 0 else { return nil }
        let dollars = NSDecimalNumber(decimal: Decimal(cents) / Decimal(100))
        return NumberFormatter.captureCurrency.string(from: dollars) ?? "$\(cents / 100)"
    }
}
