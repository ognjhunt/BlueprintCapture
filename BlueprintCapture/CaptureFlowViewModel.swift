import Foundation
import Combine
import CoreLocation
import AVFoundation
import CoreMotion
import MapKit

struct SpaceReviewSeed: Identifiable, Equatable {
    let id: String
    let title: String
    let address: String?
    let payoutRange: ClosedRange<Int>?
    let captureJobId: String?
    let buyerRequestId: String?
    let siteSubmissionId: String?
    let regionId: String?
    let rightsProfile: String?
    let requestedOutputs: [String]
    let suggestedContext: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        address: String? = nil,
        payoutRange: ClosedRange<Int>? = nil,
        captureJobId: String? = nil,
        buyerRequestId: String? = nil,
        siteSubmissionId: String? = nil,
        regionId: String? = nil,
        rightsProfile: String? = nil,
        requestedOutputs: [String] = ["qualification", "review_intake"],
        suggestedContext: String? = nil
    ) {
        self.id = id
        self.title = title
        self.address = address
        self.payoutRange = payoutRange
        self.captureJobId = captureJobId
        self.buyerRequestId = buyerRequestId
        self.siteSubmissionId = siteSubmissionId
        self.regionId = regionId
        self.rightsProfile = rightsProfile
        self.requestedOutputs = requestedOutputs
        self.suggestedContext = suggestedContext
    }
}

private func normalizeRequestedOutputs(_ outputs: [String]) -> [String] {
    var normalized: [String] = []
    for output in outputs {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !normalized.contains(trimmed) else { continue }
        normalized.append(trimmed)
    }
    if normalized.contains("preview_simulation") && !normalized.contains("deeper_evaluation") {
        normalized.append("deeper_evaluation")
    }
    return normalized
}

enum SiteWorldSiteScale: String, CaseIterable, Identifiable {
    case smallSimple = "small_simple"
    case medium
    case multiZone = "multi_zone"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smallSimple:
            return "Small / Simple"
        case .medium:
            return "Medium"
        case .multiZone:
            return "Multi-zone"
        }
    }

    var subtitle: String {
        switch self {
        case .smallSimple:
            return "Single route with one clean return"
        case .medium:
            return "Main spine with shared checkpoints"
        case .multiZone:
            return "Hub-and-spoke zones with returns"
        }
    }
}

enum SiteWorldReviewTone: String, Equatable {
    case ready
    case caution
    case actionRequired

    var title: String {
        switch self {
        case .ready:
            return "Ready"
        case .caution:
            return "Needs Next Pass"
        case .actionRequired:
            return "Needs Recapture"
        }
    }
}

struct SiteWorldPassBrief: Equatable {
    let role: String
    let title: String
    let summary: String
    let requiredCheckpointTarget: Int
    let requiredPrompt: String
    let exactPrompts: [String]
}

struct SiteWorldPassReview: Equatable {
    let passAttemptIndex: Int
    let passRole: String
    let title: String
    let tone: SiteWorldReviewTone
    let score: Int
    let summary: String
    let completedItems: [String]
    let missingItems: [String]
    let weakSignalSummary: String?
    let nextActionLabel: String?
    let canFinishWorkflow: Bool
    let shouldAdvanceWorkflow: Bool
    let completedRequiredPasses: Int
    let totalRequiredPasses: Int
    let exactPrompts: [String]
}

@MainActor
final class CaptureFlowViewModel: NSObject, ObservableObject {
    enum Step {
        case collectProfile
        case confirmLocation
        case requestPermissions
        case readyToCapture
    }

    enum FinishedCaptureActionState: Equatable {
        case idle
        case generatingIntake
        case exporting
        case failed(String)
    }

    enum FlowMode: Equatable {
        case standard
        case spaceReview(seed: SpaceReviewSeed?)
    }

    @Published var profile: UserProfile = .placeholder
    @Published var step: Step = .collectProfile
    @Published var isOnboarded: Bool = false
    @Published var currentAddress: String?
    @Published var locationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationError: String?
    @Published var cameraAuthorized: Bool = false
    @Published var microphoneAuthorized: Bool = false
    @Published var motionAuthorized: Bool = false
    @Published var addressSearchResults: [AddressResult] = []
    @Published var isSearchingAddress = false
    @Published private(set) var uploadStatuses: [UploadStatus] = []
    @Published var pendingCaptureRequest: CaptureUploadRequest?
    @Published var pendingCaptureTargetName: String?
    @Published var pendingCapturePayoutRange: ClosedRange<Int>?
    @Published var finishedCaptureActionState: FinishedCaptureActionState = .idle
    @Published var manualIntakeDraft: CaptureManualIntakeDraft?
    @Published var shareSheetItem: ShareSheetItem?
    @Published var spaceContextNotes: String = ""
    @Published var confirmedCaptureGuidelines = false
    @Published var siteWorldSiteScale: SiteWorldSiteScale = .medium
    @Published var selectedCriticalZoneAnchors: Set<CaptureSemanticAnchorType> = []
    @Published private(set) var siteWorldWorkflowConfigured = false
    @Published private(set) var pendingSiteWorldPassReview: SiteWorldPassReview?
    @Published private(set) var completedWorkflowPassCount: Int = 0

    /// Stores current target info for the active capture session (set before starting capture)
    var currentTargetInfo: (name: String, estimatedPayoutRange: ClosedRange<Int>)?
    let flowMode: FlowMode

    let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    // Google Places
    private let placesAutocomplete: PlacesAutocompleteServiceProtocol = PlacesAutocompleteService()
    private let placesDetails: PlacesDetailsServiceProtocol = PlacesDetailsService()
    private var placesSessionToken: String?
    private let motionManager = CMMotionActivityManager()
    let captureManager: VideoCaptureManager

    private var hasRequestedPermissions = false
    private let onboardingKey = "com.blueprint.isOnboarded"

    /// Stable site ID for open captures within this app session. Allows repeated captures
    /// of the same facility to share a site_id even without a targetId or reservationId.
    private let openCaptureSiteId: String = UUID().uuidString

    /// Shared across all recordings in a single app session (multiple passes at one facility visit).
    private let siteVisitId: String = UUID().uuidString

    /// Stable route ID for this session. Shared across passes of the same intended path.
    private let captureRouteId: String = UUID().uuidString

    /// Tracks how many recording attempts have been made in this session.
    private var capturePassAttemptIndex: Int = 0

    private let uploadService: CaptureUploadServiceProtocol
    private let targetStateService: TargetStateServiceProtocol
    private let intakeResolutionService: IntakeResolutionServiceProtocol
    private let exportService: CaptureExportServiceProtocol
    private let creatorAPIService: APIService
    private var uploadStatusMap: [UUID: UploadStatus] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var searchDebounceTask: Task<Void, Never>?
    private var currentSearchQuery: String = ""
    private var pendingPostCaptureAction: PendingPostCaptureAction?
    private var selectedAddressResult: AddressResult?

    init(flowMode: FlowMode = .standard,
         uploadService: CaptureUploadServiceProtocol = CaptureUploadService.shared,
         targetStateService: TargetStateServiceProtocol = TargetStateService(),
         intakeResolutionService: IntakeResolutionServiceProtocol = IntakeResolutionService(),
         exportService: CaptureExportServiceProtocol = CaptureExportService(),
         creatorAPIService: APIService = .shared) {
        self.flowMode = flowMode
        self.uploadService = uploadService
        self.targetStateService = targetStateService
        self.intakeResolutionService = intakeResolutionService
        self.exportService = exportService
        self.creatorAPIService = creatorAPIService
        self.captureManager = VideoCaptureManager()
        super.init()
        locationManager.delegate = self
        cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let audioSession = AVAudioSession.sharedInstance()
        microphoneAuthorized = audioSession.recordPermission == .granted
        motionAuthorized = MotionPermissionHelper.isAuthorized

        // Check if user has already completed onboarding
        isOnboarded = UserDefaults.standard.bool(forKey: onboardingKey)

        observeUploadEvents()

        if case .spaceReview(let seed) = flowMode {
            currentAddress = seed?.address
            spaceContextNotes = seed?.suggestedContext ?? ""
            if let seed, let payoutRange = seed.payoutRange {
                currentTargetInfo = (name: seed.title, estimatedPayoutRange: payoutRange)
            }
        }
    }

    func loadProfile() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        profile = .sample
        
        // If user is already onboarded, skip profile review and go to location confirmation
        if isOnboarded {
            step = .confirmLocation
        }
    }
    
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: onboardingKey)
        isOnboarded = true
    }

    var isSpaceReviewMode: Bool {
        if case .spaceReview = flowMode { return true }
        return false
    }

    /// True when the address was pre-filled from a search result (not GPS).
    var hasSeedAddress: Bool {
        if case .spaceReview(let seed) = flowMode { return seed?.address != nil }
        return false
    }

    var canConfirmAddress: Bool {
        guard currentAddress != nil else { return false }
        guard isSpaceReviewMode else { return true }
        return !spaceContextNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && confirmedCaptureGuidelines
    }

    var spaceReviewChecklist: [String] {
        [
            "Capture only common areas you can visibly access.",
            "Avoid faces, screens, paperwork, and posted private information.",
            "Respect restricted zones and any on-site staff direction."
        ]
    }

    var siteWorldCriticalZoneOptions: [CaptureSemanticAnchorType] {
        [.dockTurn, .handoffPoint, .floorTransition, .restrictedBoundary, .controlPanel]
    }

    var siteWorldRoutePlanSummary: [String] {
        switch siteWorldSiteScale {
        case .smallSimple:
            return [
                "Lock at the entrance, capture one clean outbound route, then return on the same path.",
                "Pause once at the far end and once at a shared threshold before closing the loop."
            ]
        case .medium:
            return [
                "Lock at the entrance, follow the main spine, and pause at every doorway or intersection that branches the route.",
                "Add a reverse-direction revisit before the final loop closure."
            ]
        case .multiZone:
            return [
                "Lock at the entrance, use one hub or spine, and treat each zone as an out-and-back branch.",
                "Do not leave a zone until you have a shared threshold checkpoint and a return to the hub."
            ]
        }
    }

    var siteWorldRequiredRules: [String] {
        var rules = [
            "Entrance lock: hold still at the entry for 3 seconds before walking.",
            "Shared checkpoints: stop at doorway, intersection, dock turn, or other topology changes.",
            "Weak signal recovery: if tracking degrades, stop and reacquire fixed structure before continuing."
        ]
        switch siteWorldSiteScale {
        case .smallSimple:
            rules.append("Loop close back to the entry or main starting threshold.")
        case .medium:
            rules.append("Run one reverse revisit on the main spine before closing the loop.")
        case .multiZone:
            rules.append("Return to the hub or spine after each zone before moving to the next one.")
        }
        if !selectedCriticalZoneAnchors.isEmpty {
            rules.append("Revisit every selected critical zone from the opposite direction before finishing.")
        }
        return rules
    }

    var siteWorldOptionalRules: [String] {
        [
            "Add manual notes only when access limits or unusual constraints matter downstream.",
            "Mark extra checkpoints if a space is visually repetitive, but do not wander just to raise the count.",
            "Take an extra static sweep only when you are already at a strong shared checkpoint."
        ]
    }

    func requestLocation() {
        completeOnboarding()
        guard CLLocationManager.locationServicesEnabled() else {
            locationError = "Location services are disabled. Enable them in Settings to continue."
            step = .confirmLocation
            return
        }
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
        step = .confirmLocation
    }

    func confirmAddress() {
        guard canConfirmAddress else { return }
        guard cameraAuthorized, microphoneAuthorized, motionAuthorized else {
            step = .requestPermissions
            return
        }
        moveToCapture()
    }

    /// Debounced address search with proper cleanup and state management
    /// Matches the approach from the React autocomplete solution
    func searchAddresses(query: String) async {
        // Cancel any pending search task
        searchDebounceTask?.cancel()
        
        // Update current query immediately
        currentSearchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Clear results if query is too short
        guard trimmed.count >= 3 else {
            await MainActor.run { 
                self.addressSearchResults = []
                self.isSearchingAddress = false
            }
            // Reset session token when clearing search
            placesSessionToken = nil
            return
        }
        
        // Set loading state immediately
        await MainActor.run { self.isSearchingAddress = true }
        
        // Create debounced search task (350ms delay matching React solution)
        searchDebounceTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000) // 350ms
                
                // Check if this task was cancelled during sleep
                guard !Task.isCancelled else {
                    print("🔍 [Autocomplete] Search cancelled for '\(trimmed)'")
                    return
                }
                
                // Perform the actual search
                await performAddressSearch(query: trimmed)
            } catch {
                // Task was cancelled
                print("🔍 [Autocomplete] Search task cancelled")
            }
        }
    }
    
    /// Internal method that performs the actual autocomplete search
    /// This is called after debounce delay
    private func performAddressSearch(query: String) async {
        // Ensure session token exists (reuse across autocomplete requests, reset on selection)
        if placesSessionToken == nil {
            placesSessionToken = UUID().uuidString
            print("🔑 [Autocomplete] Created new session token: \(placesSessionToken ?? "")")
        }
        
        // Check if query still matches current query (prevent stale results)
        guard query == currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else {
            print("🔍 [Autocomplete] Query changed, skipping stale search for '\(query)'")
            await MainActor.run { self.isSearchingAddress = false }
            return
        }
        
        defer { 
            Task { @MainActor in 
                self.isSearchingAddress = false 
            } 
        }
        
        if RuntimeConfig.current.availability(for: .nearbyDiscovery).isEnabled {
            do {
                let suggestions = try await placesAutocomplete.autocomplete(
                    input: query,
                    sessionToken: placesSessionToken ?? UUID().uuidString,
                    origin: nil,
                    radiusMeters: nil
                )
                print("🔍 [Autocomplete] Got \(suggestions.count) suggestions for '\(query)'")
                
                // Check again if query is still current
                guard query == currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    print("🔍 [Autocomplete] Query changed after fetch, discarding results")
                    return
                }
                
                guard !suggestions.isEmpty else {
                    print("⚠️ [Autocomplete] No suggestions returned, falling back to MapKit")
                    throw NSError(domain: "AutocompleteError", code: -1, userInfo: nil)
                }
                
                // Fetch details for display-friendly address fragments
                let details = try await placesDetails.fetchDetails(placeIds: suggestions.map { $0.placeId })
                print("📋 [Places Details] Got details for \(details.count) of \(suggestions.count) suggestions")
                
                // Final check if query is still current before showing results
                guard query == currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    print("🔍 [Autocomplete] Query changed after details fetch, discarding results")
                    return
                }
                
                let byId = Dictionary(uniqueKeysWithValues: details.map { ($0.placeId, $0) })
                let mapped: [AddressResult] = suggestions.compactMap { s in
                    let d = byId[s.placeId]
                    let title = s.primaryText
                    let subtitle = s.secondaryText.isEmpty ? (d?.formattedAddress ?? "") : s.secondaryText
                    return AddressResult(
                        title: title,
                        subtitle: subtitle,
                        completionTitle: title,
                        completionSubtitle: subtitle,
                        placeId: s.placeId,
                        formattedAddress: d?.formattedAddress ?? subtitle,
                        lat: d?.lat,
                        lng: d?.lng,
                        accuracyM: nil,
                        placeTypes: d?.types ?? s.types
                    )
                }
                print("✅ [Autocomplete] Displaying \(mapped.count) search results")
                await MainActor.run { self.addressSearchResults = Array(mapped.prefix(5)) }
                return
            } catch {
                print("❌ [Autocomplete] Error: \(error.localizedDescription)")
                // Fall through to MapKit on error
            }
        }

        // MapKit Fallback
        print("📍 [MapKit] Falling back to MapKit search for '\(query)'")
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = query
        let search = MKLocalSearch(request: searchRequest)
        do {
            let response = try await search.start()
            
            // Final check if query is still current
            guard query == currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else {
                print("📍 [MapKit] Query changed after fetch, discarding results")
                return
            }
            
            let results = response.mapItems.prefix(5).map { mapItem in
                let title = mapItem.name ?? "Unknown"
                let subtitle = mapItem.placemark.locality ?? mapItem.placemark.administrativeArea ?? ""
                return AddressResult(
                    title: title,
                    subtitle: subtitle,
                    completionTitle: title,
                    completionSubtitle: subtitle,
                    placeId: nil,
                    formattedAddress: mapItem.placemark.title,
                    lat: mapItem.placemark.location?.coordinate.latitude,
                    lng: mapItem.placemark.location?.coordinate.longitude,
                    accuracyM: mapItem.placemark.location?.horizontalAccuracy,
                    placeTypes: []
                )
            }
            print("📍 [MapKit] Displaying \(results.count) search results")
            await MainActor.run { self.addressSearchResults = Array(results) }
        } catch {
            print("❌ [MapKit Search] Error: \(error.localizedDescription)")
            await MainActor.run { self.addressSearchResults = [] }
        }
    }
    
    func selectAddress(_ result: AddressResult) {
        currentAddress = result.formattedAddress ?? "\(result.title), \(result.subtitle)"
        addressSearchResults = []
        selectedAddressResult = result
        // Clear session token on selection (matching React solution approach)
        placesSessionToken = nil
    }

    func requestPermissions() {
        guard !hasRequestedPermissions else {
            evaluatePermissions()
            return
        }
        hasRequestedPermissions = true
        Task {
            await requestCameraAccess()
            await requestMicrophoneAccess()
            await requestMotionAccess()
            await MainActor.run {
                evaluatePermissions()
            }
        }
    }

    private func requestCameraAccess() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run {
            cameraAuthorized = granted
        }
    }

    private func requestMicrophoneAccess() async {
        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        await MainActor.run {
            microphoneAuthorized = granted
        }
    }

    private func requestMotionAccess() async {
        let authorized = await MotionPermissionHelper.requestAuthorization(activityManager: motionManager)
        await MainActor.run {
            motionAuthorized = authorized
        }
    }

    private func evaluatePermissions() {
        if cameraAuthorized && microphoneAuthorized && motionAuthorized {
            moveToCapture()
        }
    }

    private func moveToCapture() {
        step = .readyToCapture
        captureManager.configureSession()
        captureManager.startSession()
    }

    func handleRecordingFinished(artifacts: VideoCaptureManager.RecordingArtifacts, targetId: String?, reservationId: String?) {
        print("📦 [CaptureFlowViewModel] handleRecordingFinished targetId=\(targetId ?? "nil") reservationId=\(reservationId ?? "nil") package=\(artifacts.packageURL.lastPathComponent)")
        let reviewSeed: SpaceReviewSeed? = {
            if case .spaceReview(let seed) = flowMode { return seed }
            return nil
        }()
        let jobId = reviewSeed?.captureJobId ?? reservationId ?? targetId ?? UUID().uuidString
        let requestedOutputs = normalizeRequestedOutputs(
            reviewSeed?.requestedOutputs
                ?? (isSpaceReviewMode
                    ? ["qualification", "review_intake", "preview_simulation", "deeper_evaluation"]
                    : ["qualification", "preview_simulation", "deeper_evaluation"])
        )
        let rightsProfile = reviewSeed?.rightsProfile ?? (isSpaceReviewMode ? "review_required" : nil)
        let contextParts = [currentTargetInfo?.name, currentAddress, spaceContextNotes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty]

        // Derive stable site identity. Priority: buyer target > reservation > session-stable UUID.
        let siteId: String
        let siteIdSource: String
        if let targetId = targetId?.trimmingCharacters(in: .whitespacesAndNewlines), !targetId.isEmpty {
            siteId = targetId
            siteIdSource = "buyer_request"
        } else if let reservationId = reservationId?.trimmingCharacters(in: .whitespacesAndNewlines), !reservationId.isEmpty {
            siteId = reservationId
            siteIdSource = "site_submission"
        } else {
            siteId = openCaptureSiteId
            siteIdSource = "open_capture"
        }
        let siteIdentity = SiteIdentity(
            siteId: siteId,
            siteIdSource: siteIdSource,
            placeId: selectedAddressResult?.placeId,
            siteName: currentTargetInfo?.name ?? reviewSeed?.title,
            addressFull: currentAddress,
            geo: selectedAddressResult?.lat.flatMap { latitude in
                selectedAddressResult?.lng.map { longitude in
                    SiteGeoPoint(
                        latitude: latitude,
                        longitude: longitude,
                        accuracyM: selectedAddressResult?.accuracyM ?? 25.0
                    )
                }
            },
            buildingId: nil,
            floorId: nil,
            roomId: nil,
            zoneId: nil
        )

        siteWorldWorkflowConfigured = true
        capturePassAttemptIndex += 1
        let hold = captureManager.detectedEntryAnchorHold
        let passRole = currentPlannedPassRole
        let coordinateFrameSessionId = captureManager.latestRecordingSessionId
        let passReview = buildSiteWorldPassReview(
            passAttemptIndex: capturePassAttemptIndex,
            passRole: passRole,
            hold: hold,
            anchorEvents: captureManager.semanticAnchorEvents,
            monitor: captureManager.qualityMonitor
        )
        let completedRequiredPasses = completedWorkflowPassCount + (passReview.shouldAdvanceWorkflow ? 1 : 0)
        let totalRequiredPasses = workflowPassSequence().count
        let pendingReview = SiteWorldPassReview(
            passAttemptIndex: passReview.passAttemptIndex,
            passRole: passReview.passRole,
            title: passReview.title,
            tone: passReview.tone,
            score: passReview.score,
            summary: passReview.summary,
            completedItems: passReview.completedItems,
            missingItems: passReview.missingItems,
            weakSignalSummary: passReview.weakSignalSummary,
            nextActionLabel: nextWorkflowActionLabel(
                after: passRole,
                shouldAdvance: passReview.shouldAdvanceWorkflow,
                hasWeakSignalConcern: captureManager.qualityMonitor.hasWeakSignalConcern
            ),
            canFinishWorkflow: completedRequiredPasses >= totalRequiredPasses && !captureManager.qualityMonitor.hasWeakSignalConcern,
            shouldAdvanceWorkflow: passReview.shouldAdvanceWorkflow,
            completedRequiredPasses: min(completedRequiredPasses, totalRequiredPasses),
            totalRequiredPasses: totalRequiredPasses,
            exactPrompts: passReview.exactPrompts
        )
        if passReview.shouldAdvanceWorkflow {
            completedWorkflowPassCount = min(completedRequiredPasses, totalRequiredPasses)
        }
        let captureTopology = CaptureTopologyMetadata(
            captureSessionId: siteVisitId,
            routeId: captureRouteId,
            passId: UUID().uuidString,
            passIndex: capturePassAttemptIndex,
            intendedPassRole: passRole,
            entryAnchorId: hold?.anchorId,
            returnAnchorId: passRole == "loop_closure" && captureManager.semanticAnchorEvents.contains(where: { $0.anchorType == .entrance || $0.anchorType == .exitPoint }) ? "semantic_entrance" : nil,
            entryAnchorTCaptureSec: hold?.tCaptureSec,
            entryAnchorHoldDurationSec: hold?.durationSec,
            siteVisitId: siteVisitId,
            coordinateFrameSessionId: coordinateFrameSessionId,
            arkitSessionId: coordinateFrameSessionId
        )

        // iPhone captures default to requesting site_world_candidate mode.
        // Resolved mode is determined at finalization time from actual evidence.
        let captureMode = CaptureModeMetadata(
            requestedMode: "site_world_candidate",
            resolvedMode: "site_world_candidate",
            downgradeReason: nil
        )

        let metadata = CaptureUploadMetadata(
            id: UUID(),
            targetId: targetId,
            reservationId: reservationId,
            jobId: jobId,
            captureJobId: reviewSeed?.captureJobId ?? jobId,
            buyerRequestId: reviewSeed?.buyerRequestId,
            siteSubmissionId: reviewSeed?.siteSubmissionId ?? jobId,
            regionId: reviewSeed?.regionId,
            creatorId: profile.id.uuidString,
            capturedAt: Date(),
            uploadedAt: nil,
            captureSource: .iphoneVideo,
            specialTaskType: isSpaceReviewMode ? .openCapture : (targetId == nil ? .operatorApproved : .curatedNearby),
            priorityWeight: 1.0,
            quotedPayoutCents: currentTargetInfo.map { $0.estimatedPayoutRange.upperBound * 100 },
            rightsProfile: rightsProfile,
            requestedOutputs: requestedOutputs,
            intakePacket: nil,
            intakeMetadata: nil,
            taskHypothesis: nil,
            scaffoldingPacket: CaptureScaffoldingPacket(
                scaffoldingUsed: siteWorldScaffoldingUsed(for: passRole),
                coveragePlan: siteWorldCoveragePlan(for: passRole),
                calibrationAssets: [],
                scaleAnchorAssets: [],
                checkpointAssets: [],
                uncertaintyPriors: ["missing_intake": 0.6]
            ),
            captureModality: nil,
            evidenceTier: nil,
            captureContextHint: contextParts.compactMap { $0 }.joined(separator: " | ").nilIfEmpty,
            sceneMemory: SceneMemoryCaptureMetadata(
                continuityScore: Double(pendingReview.score) / 100.0,
                lightingConsistency: "unknown",
                dynamicObjectDensity: "unknown",
                operatorNotes: siteWorldOperatorNotes(from: pendingReview),
                inaccessibleAreas: [],
                semanticAnchorsObserved: Array(Set(captureManager.semanticAnchorEvents.map { $0.anchorType.rawValue })).sorted(),
                relocalizationCount: captureManager.qualityMonitor.relocalizationCount,
                overlapCheckpointCount: captureManager.semanticAnchorEvents.count
            ),
            captureRights: CaptureRightsMetadata(
                derivedSceneGenerationAllowed: !isSpaceReviewMode,
                dataLicensingAllowed: !isSpaceReviewMode,
                payoutEligible: !isSpaceReviewMode,
                consentStatus: isSpaceReviewMode ? .policyOnly : .unknown,
                permissionDocumentURI: nil,
                consentScope: [],
                consentNotes: isSpaceReviewMode ? spaceReviewChecklist : []
            ),
            siteIdentity: siteIdentity,
            captureTopology: captureTopology,
            captureMode: captureMode,
            semanticAnchors: captureManager.semanticAnchorEvents
        )
        let request = CaptureUploadRequest(packageURL: artifacts.packageURL, metadata: metadata)

        pendingCaptureRequest = request
        pendingSiteWorldPassReview = pendingReview
        pendingCaptureTargetName = currentTargetInfo?.name ?? reviewSeed?.title
        pendingCapturePayoutRange = currentTargetInfo?.estimatedPayoutRange ?? reviewSeed?.payoutRange
        finishedCaptureActionState = .idle
        currentTargetInfo = nil
        print("📦 [CaptureFlowViewModel] Pending capture ready jobId=\(jobId) id=\(metadata.id)")
    }

    var currentPlannedPassRole: String {
        plannedPassRole(for: completedWorkflowPassCount + 1)
    }

    var currentSiteWorldPassBrief: SiteWorldPassBrief {
        passBrief(for: currentPlannedPassRole)
    }

    var highlightedAnchorTypesForCurrentPass: Set<CaptureSemanticAnchorType> {
        switch currentPlannedPassRole {
        case "revisit":
            return Set([CaptureSemanticAnchorType.entrance, .doorway, .corridorIntersection, .exitPoint]).union(selectedCriticalZoneAnchors)
        case "loop_closure":
            return Set([CaptureSemanticAnchorType.entrance, .doorway, .corridorIntersection, .exitPoint])
        case "critical_zone_revisit":
            return selectedCriticalZoneAnchors.isEmpty
                ? Set(siteWorldCriticalZoneOptions)
                : selectedCriticalZoneAnchors
        default:
            return Set([CaptureSemanticAnchorType.doorway, .corridorIntersection, .dockTurn, .handoffPoint, .floorTransition, .restrictedBoundary]).union(selectedCriticalZoneAnchors)
        }
    }

    func configureSiteWorldWorkflow() {
        siteWorldWorkflowConfigured = true
    }

    func setCriticalZone(_ anchorType: CaptureSemanticAnchorType, enabled: Bool) {
        if enabled {
            selectedCriticalZoneAnchors.insert(anchorType)
        } else {
            selectedCriticalZoneAnchors.remove(anchorType)
        }
    }

    func prepareForNextWorkflowPass() {
        pendingCaptureRequest = nil
        pendingCaptureTargetName = nil
        pendingCapturePayoutRange = nil
        finishedCaptureActionState = .idle
        manualIntakeDraft = nil
        pendingPostCaptureAction = nil
        pendingSiteWorldPassReview = nil
    }

    func resetSiteWorldWorkflowSession() {
        siteWorldWorkflowConfigured = false
        pendingSiteWorldPassReview = nil
        completedWorkflowPassCount = 0
        capturePassAttemptIndex = 0
        selectedCriticalZoneAnchors = []
        siteWorldSiteScale = .medium
    }

    func livePrompt(for monitor: CaptureQualityMonitor, entryHold: VideoCaptureManager.EntryAnchorHold?, anchorEvents: [CaptureSemanticAnchorEvent]) -> String {
        if entryHold == nil {
            return "Stand at the main entry point. Hold still for 3 seconds. Slowly pan left, center, right. Keep the door frame, floor edge, and nearby wall in view."
        }
        if let recoveryPrompt = monitor.recoveryPrompt {
            return recoveryPrompt
        }
        let sharedCheckpointCount = anchorEvents.filter { sharedCheckpointAnchorTypes.contains($0.anchorType) }.count
        let target = currentSiteWorldPassBrief.requiredCheckpointTarget
        switch currentPlannedPassRole {
        case "revisit":
            return "Turn back and reacquire the last checkpoint from the reverse direction before leaving this zone."
        case "loop_closure":
            return "Return to your start anchor. Match the original entrance view as closely as practical, then hold for 3 seconds."
        case "critical_zone_revisit":
            return "Capture the static boundary, approach path, and exit path. Revisit once from the opposite direction."
        default:
            if sharedCheckpointCount < target {
                return "At the next doorway or intersection, stop at the threshold. Show left frame, center opening, right frame. Then continue."
            }
            if let lastCheckpointT = anchorEvents.compactMap(\.tCaptureSec).max(),
               monitor.elapsedSeconds - lastCheckpointT > 35 {
                return "Before leaving this shared area, pause and show the last checkpoint again for 2 seconds."
            }
            return currentSiteWorldPassBrief.requiredPrompt
        }
    }

    func liveSupportPrompts(for monitor: CaptureQualityMonitor, anchorEvents: [CaptureSemanticAnchorEvent]) -> [String] {
        var prompts = ["Prefer fixed building structure. Avoid following people, forklifts, carts, or temporary pallets."]
        if !selectedCriticalZoneAnchors.isEmpty {
            let remainingCritical = selectedCriticalZoneAnchors.subtracting(Set(anchorEvents.map(\.anchorType)))
            if !remainingCritical.isEmpty {
                let labels = remainingCritical.map(\.displayLabel).sorted().joined(separator: ", ")
                prompts.append("Still need critical zones: \(labels).")
            }
        }
        if monitor.hasWeakSignalConcern {
            prompts.append("Weak segment detected. Reacquire a recent checkpoint before moving deeper into the site.")
        } else {
            prompts.append("Shared checkpoints: \(anchorEvents.filter { sharedCheckpointAnchorTypes.contains($0.anchorType) }.count)/\(currentSiteWorldPassBrief.requiredCheckpointTarget)")
        }
        return Array(prompts.prefix(2))
    }

    func liveStatusChips(for monitor: CaptureQualityMonitor, entryHold: VideoCaptureManager.EntryAnchorHold?, anchorEvents: [CaptureSemanticAnchorEvent]) -> [String] {
        var chips: [String] = []
        chips.append(entryHold == nil ? "Entry lock pending" : "Entry locked")
        chips.append("Checkpoints \(anchorEvents.filter { sharedCheckpointAnchorTypes.contains($0.anchorType) }.count)/\(currentSiteWorldPassBrief.requiredCheckpointTarget)")
        if monitor.hasWeakSignalConcern {
            chips.append("Weak signal \(Int(monitor.limitedTrackingSeconds))s")
        }
        if !selectedCriticalZoneAnchors.isEmpty {
            let matched = selectedCriticalZoneAnchors.intersection(Set(anchorEvents.map(\.anchorType))).count
            chips.append("Critical \(matched)/\(selectedCriticalZoneAnchors.count)")
        }
        return chips
    }

    private func plannedPassRole(for stageIndex: Int) -> String {
        let roles = workflowPassSequence()
        guard !roles.isEmpty else { return "primary" }
        let clampedIndex = min(max(stageIndex - 1, 0), roles.count - 1)
        return roles[clampedIndex]
    }

    private func workflowPassSequence() -> [String] {
        var roles: [String]
        switch siteWorldSiteScale {
        case .smallSimple:
            roles = ["primary", "loop_closure"]
        case .medium, .multiZone:
            roles = ["primary", "revisit", "loop_closure"]
        }
        if !selectedCriticalZoneAnchors.isEmpty {
            roles.append("critical_zone_revisit")
        }
        return roles
    }

    private var sharedCheckpointAnchorTypes: Set<CaptureSemanticAnchorType> {
        [.doorway, .corridorIntersection, .dockTurn, .handoffPoint, .floorTransition, .restrictedBoundary]
    }

    private func passBrief(for role: String) -> SiteWorldPassBrief {
        switch role {
        case "revisit":
            return SiteWorldPassBrief(
                role: role,
                title: "Revisit Pass",
                summary: "Reverse through shared checkpoints before closing the route.",
                requiredCheckpointTarget: max(1, currentCheckpointTarget / 2),
                requiredPrompt: "Turn back and reacquire the last checkpoint from the reverse direction before leaving this zone.",
                exactPrompts: [
                    "Turn back and reacquire the last checkpoint from the reverse direction before leaving this zone.",
                    "Pause at the intersection. Sweep each branch briefly, then continue down your chosen path."
                ]
            )
        case "loop_closure":
            return SiteWorldPassBrief(
                role: role,
                title: "Loop Closure",
                summary: "Return to the entrance or hub and match the starting view.",
                requiredCheckpointTarget: 1,
                requiredPrompt: "Return to your start anchor. Match the original entrance view as closely as practical, then hold for 3 seconds.",
                exactPrompts: [
                    "Return to your start anchor. Match the original entrance view as closely as practical, then hold for 3 seconds.",
                    "Before leaving this shared area, pause and show the last checkpoint again for 2 seconds."
                ]
            )
        case "critical_zone_revisit":
            return SiteWorldPassBrief(
                role: role,
                title: "Critical Zone Revisit",
                summary: "Reacquire operationally critical boundaries and handoff geometry.",
                requiredCheckpointTarget: max(1, selectedCriticalZoneAnchors.count),
                requiredPrompt: "Capture the static boundary, approach path, and exit path. Revisit once from the opposite direction.",
                exactPrompts: [
                    "This is a critical zone. Capture the static boundary, approach path, and exit path. Revisit once from the opposite direction.",
                    "Match the earlier view within a few steps. Hold briefly. Show the same threshold or boundary geometry again."
                ]
            )
        default:
            return SiteWorldPassBrief(
                role: "primary",
                title: "Primary Route",
                summary: primaryPassSummary,
                requiredCheckpointTarget: currentCheckpointTarget,
                requiredPrompt: "Walk forward slowly. Pause at every major threshold or branch before moving on.",
                exactPrompts: [
                    "Stand at the main entry point. Hold still for 3 seconds. Slowly pan left, center, right. Keep the door frame, floor edge, and nearby wall in view.",
                    "At this doorway, stop at the threshold. Show left frame, center opening, right frame. Then continue."
                ]
            )
        }
    }

    private var currentCheckpointTarget: Int {
        switch siteWorldSiteScale {
        case .smallSimple:
            return 2
        case .medium:
            return 4
        case .multiZone:
            return 6
        }
    }

    private var primaryPassSummary: String {
        switch siteWorldSiteScale {
        case .smallSimple:
            return "One clean outbound route, one far-end checkpoint, then return to the start."
        case .medium:
            return "Cover the main spine and pause at doorways, intersections, and shared thresholds."
        case .multiZone:
            return "Use a hub or spine and capture each zone as an out-and-back branch."
        }
    }

    private func siteWorldCoveragePlan(for passRole: String) -> [String] {
        var plan = siteWorldRoutePlanSummary
        plan.append(passBrief(for: passRole).summary)
        if !selectedCriticalZoneAnchors.isEmpty {
            let labels = selectedCriticalZoneAnchors.map(\.displayLabel).sorted().joined(separator: ", ")
            plan.append("Critical zone revisits requested for: \(labels).")
        }
        return plan
    }

    private func siteWorldScaffoldingUsed(for passRole: String) -> [String] {
        var scaffolding = ["site_world_candidate", "entry_anchor_hold", "shared_checkpoint_prompts", "pass_role_\(passRole)"]
        if siteWorldSiteScale == .multiZone {
            scaffolding.append("hub_return_plan")
        }
        if !selectedCriticalZoneAnchors.isEmpty {
            scaffolding.append("critical_zone_revisits")
        }
        return scaffolding
    }

    private func siteWorldOperatorNotes(from review: SiteWorldPassReview) -> [String] {
        var notes = spaceContextNotes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty.map { [$0] } ?? []
        notes.append("site_world_scale:\(siteWorldSiteScale.rawValue)")
        if !selectedCriticalZoneAnchors.isEmpty {
            notes.append("critical_zones:\(selectedCriticalZoneAnchors.map(\.rawValue).sorted().joined(separator: ","))")
        }
        if let weakSignalSummary = review.weakSignalSummary {
            notes.append(weakSignalSummary)
        }
        return notes
    }

    private func buildSiteWorldPassReview(
        passAttemptIndex: Int,
        passRole: String,
        hold: VideoCaptureManager.EntryAnchorHold?,
        anchorEvents: [CaptureSemanticAnchorEvent],
        monitor: CaptureQualityMonitor
    ) -> SiteWorldPassReview {
        let brief = passBrief(for: passRole)
        let anchorTypes = Set(anchorEvents.map(\.anchorType))
        let sharedCheckpointCount = anchorEvents.filter { sharedCheckpointAnchorTypes.contains($0.anchorType) }.count
        let criticalMatches = selectedCriticalZoneAnchors.intersection(anchorTypes)
        let hasLoopClosureAnchor = anchorTypes.contains(.entrance) || anchorTypes.contains(.exitPoint) || hold != nil
        var completedItems: [String] = []
        var missingItems: [String] = []

        if hold != nil {
            completedItems.append("Entrance localization hold captured.")
        } else {
            missingItems.append("Entrance localization hold is required before the route counts.")
        }

        switch passRole {
        case "revisit":
            if sharedCheckpointCount >= brief.requiredCheckpointTarget {
                completedItems.append("Reverse-direction shared checkpoints captured.")
            } else {
                missingItems.append("Reacquire at least \(brief.requiredCheckpointTarget) doorway or intersection checkpoints in reverse.")
            }
        case "loop_closure":
            if hasLoopClosureAnchor {
                completedItems.append("Loop closure returned to the entrance or shared endpoint.")
            } else {
                missingItems.append("Return to the original entrance or shared endpoint before finishing this pass.")
            }
        case "critical_zone_revisit":
            if selectedCriticalZoneAnchors.isEmpty || !criticalMatches.isEmpty {
                completedItems.append("Critical zone revisit captured.")
            } else {
                let labels = selectedCriticalZoneAnchors.map(\.displayLabel).sorted().joined(separator: ", ")
                missingItems.append("Revisit one of the selected critical zones: \(labels).")
            }
        default:
            if sharedCheckpointCount >= brief.requiredCheckpointTarget {
                completedItems.append("Shared checkpoint target met.")
            } else {
                missingItems.append("Capture \(brief.requiredCheckpointTarget) shared checkpoints at doorways, intersections, or thresholds.")
            }
        }

        let weakSignalSummary: String? = {
            guard monitor.limitedTrackingSeconds > 0 || monitor.relocalizationCount > 0 else { return nil }
            return "weak_signal:\(Int(monitor.limitedTrackingSeconds))s limited, \(monitor.relocalizationCount) relocalizations"
        }()
        if monitor.hasWeakSignalConcern {
            missingItems.append("Tracking degraded long enough to require a targeted recapture before finishing.")
        } else if monitor.limitedTrackingSeconds > 0 {
            completedItems.append("Tracking recovered without blocking the route.")
        }

        let shouldAdvance = missingItems.isEmpty
        let score = max(20, min(100, 100 - (missingItems.count * 18) - Int(monitor.limitedTrackingSeconds.rounded())))
        let tone: SiteWorldReviewTone = missingItems.isEmpty ? .ready : (monitor.hasWeakSignalConcern ? .actionRequired : .caution)

        return SiteWorldPassReview(
            passAttemptIndex: passAttemptIndex,
            passRole: passRole,
            title: brief.title,
            tone: tone,
            score: score,
            summary: brief.summary,
            completedItems: completedItems,
            missingItems: missingItems,
            weakSignalSummary: weakSignalSummary,
            nextActionLabel: nil,
            canFinishWorkflow: false,
            shouldAdvanceWorkflow: shouldAdvance,
            completedRequiredPasses: completedWorkflowPassCount,
            totalRequiredPasses: workflowPassSequence().count,
            exactPrompts: brief.exactPrompts
        )
    }

    private func nextWorkflowActionLabel(after passRole: String, shouldAdvance: Bool, hasWeakSignalConcern: Bool) -> String? {
        if hasWeakSignalConcern {
            return passRole == "critical_zone_revisit" ? "Recapture weak segment" : "Recapture weak segments"
        }
        guard shouldAdvance else {
            switch passRole {
            case "loop_closure":
                return "Retry loop closure"
            case "critical_zone_revisit":
                return "Retry critical zone revisit"
            default:
                return "Retake \(passBrief(for: passRole).title.lowercased())"
            }
        }

        let nextRole = plannedPassRole(for: completedWorkflowPassCount + 2)
        if completedWorkflowPassCount + 1 >= workflowPassSequence().count {
            return nil
        }
        switch nextRole {
        case "revisit":
            return "Start revisit pass"
        case "loop_closure":
            return "Start loop closure"
        case "critical_zone_revisit":
            return "Revisit critical zones"
        default:
            return "Start next pass"
        }
    }

    func startPendingCaptureUpload() {
        guard let request = pendingCaptureRequest else { return }
        pendingPostCaptureAction = .upload
        Task { await resolvePendingCaptureAndContinue(request: request, action: .upload, skipResolution: true) }
    }

    func startPendingCaptureExport() {
        guard let request = pendingCaptureRequest else { return }
        pendingPostCaptureAction = .export
        Task { await resolvePendingCaptureAndContinue(request: request, action: .export, skipResolution: true) }
    }

    func submitManualIntake(_ draft: CaptureManualIntakeDraft) {
        guard let request = pendingCaptureRequest else { return }
        manualIntakeDraft = nil
        let resolvedRequest = request.withManualIntake(draft.makePacket())
        pendingCaptureRequest = resolvedRequest
        let action = pendingPostCaptureAction ?? .export
        Task { await resolvePendingCaptureAndContinue(request: resolvedRequest, action: action, skipResolution: true) }
    }

    func clearFinishedCapture() {
        pendingCaptureRequest = nil
        pendingCaptureTargetName = nil
        pendingCapturePayoutRange = nil
        finishedCaptureActionState = .idle
        manualIntakeDraft = nil
        pendingPostCaptureAction = nil
        pendingSiteWorldPassReview = nil
        if isSpaceReviewMode {
            confirmedCaptureGuidelines = false
        }
    }

    func updatePendingCaptureNotes(_ notes: String) {
        guard var request = pendingCaptureRequest else { return }
        request.metadata = request.metadata.applyingCaptureNotes(notes)
        pendingCaptureRequest = request
    }

    private func resolvePendingCaptureAndContinue(
        request: CaptureUploadRequest,
        action: PendingPostCaptureAction,
        skipResolution: Bool = false
    ) async {
        await MainActor.run {
            finishedCaptureActionState = action == .export ? .exporting : .generatingIntake
        }

        let resolution: IntakeResolutionOutcome
        if skipResolution {
            resolution = .resolved(request)
        } else {
            resolution = await intakeResolutionService.resolve(request: request)
        }

        switch resolution {
        case .resolved(let resolvedRequest):
            await MainActor.run {
                self.pendingCaptureRequest = resolvedRequest
                self.finishedCaptureActionState = .idle
            }
            switch action {
            case .upload:
                await MainActor.run {
                    self.enqueueUploadWithTargetInfo(
                        resolvedRequest,
                        targetName: self.pendingCaptureTargetName,
                        payoutRange: self.pendingCapturePayoutRange
                    )
                    self.clearFinishedCapture()
                }
            case .export:
                do {
                    let bundle = try await exportService.exportCapture(request: resolvedRequest)
                    await MainActor.run {
                        let shareURL = bundle.shareURL ?? bundle.captureRootURL
                        self.shareSheetItem = ShareSheetItem(url: shareURL)
                        self.pendingCaptureRequest = resolvedRequest
                    }
                } catch {
                    await MainActor.run {
                        self.finishedCaptureActionState = .failed(error.localizedDescription)
                    }
                }
            }
        case .needsManualEntry(let unresolvedRequest, _):
            // Alpha: AI intake is disabled — skip the manual form and proceed directly
            await resolvePendingCaptureAndContinue(request: unresolvedRequest, action: action, skipResolution: true)
        }
    }

    private func enqueueUploadWithTargetInfo(_ request: CaptureUploadRequest, targetName: String?, payoutRange: ClosedRange<Int>?) {
        // Store target info before enqueueing so we can use it when creating UploadStatus
        let id = request.metadata.id
        uploadStatusMap[id] = UploadStatus(request: request, targetName: targetName, estimatedPayoutRange: payoutRange)
        refreshUploadStatuses()

        // Now enqueue the actual upload
        uploadService.enqueue(request)
    }

    func retryUpload(id: UUID) {
        uploadService.retryUpload(id: id)
    }

    func dismissUpload(id: UUID) {
        uploadStatusMap.removeValue(forKey: id)
        refreshUploadStatuses()
    }

    private func observeUploadEvents() {
        uploadService.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleUpload(event)
            }
            .store(in: &cancellables)
    }

    private func handleUpload(_ event: CaptureUploadService.Event) {
        switch event {
        case .queued(let request):
            print("📤 [Upload] queued id=\(request.metadata.id) targetId=\(request.metadata.targetId ?? "nil")")
            // Only create new status if we don't already have one (we may have pre-created it with target info)
            if uploadStatusMap[request.metadata.id] == nil {
                uploadStatusMap[request.metadata.id] = UploadStatus(request: request)
            }
        case .progress(let id, let progress):
            print("📤 [Upload] progress id=\(id) progress=\(String(format: "%.2f", progress))")
            guard var status = uploadStatusMap[id] else { break }
            status.state = .uploading(progress: progress)
            uploadStatusMap[id] = status
        case .completed(let request):
            print("📤 [Upload] completed id=\(request.metadata.id)")
            guard var status = uploadStatusMap[request.metadata.id] else { break }
            status.metadata = request.metadata
            status.state = .completed
            uploadStatusMap[request.metadata.id] = status
            Task { [weak self] in
                guard let self else { return }
                try? await self.creatorAPIService.registerCaptureSubmission(
                    id: request.metadata.id,
                    targetAddress: status.targetName ?? self.currentAddress ?? "Submitted space",
                    capturedAt: request.metadata.capturedAt,
                    quotedPayoutCents: request.metadata.quotedPayoutCents,
                    captureJobId: request.metadata.captureJobId,
                    buyerRequestId: request.metadata.buyerRequestId,
                    siteSubmissionId: request.metadata.siteSubmissionId,
                    rightsProfile: request.metadata.rightsProfile,
                    requestedOutputs: request.metadata.requestedOutputs
                )
            }
            // Mark target as completed in Firestore so it no longer appears in Nearby
            if let targetId = request.metadata.targetId, !targetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task { [weak self] in
                    guard let self else { return }
                    do { try await self.targetStateService.complete(targetId: targetId) }
                    catch { print("⚠️ Failed to mark target completed for \(targetId): \(error.localizedDescription)") }
                }
            }
        case .failed(let request, let error):
            print("📤 [Upload] failed id=\(request.metadata.id) error=\(error.localizedDescription)")
            guard var status = uploadStatusMap[request.metadata.id] else { break }
            status.metadata = request.metadata
            status.state = .failed(message: error.localizedDescription)
            uploadStatusMap[request.metadata.id] = status
        }

        refreshUploadStatuses()
    }

    private func refreshUploadStatuses() {
        uploadStatuses = uploadStatusMap
            .values
            .sorted { $0.metadata.capturedAt > $1.metadata.capturedAt }
    }

    private enum PendingPostCaptureAction {
        case upload
        case export
    }
}

extension CaptureFlowViewModel: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationStatus = manager.authorizationStatus
        if [.authorizedAlways, .authorizedWhenInUse].contains(locationStatus) {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // Don't overwrite an address the user explicitly searched for
        guard !hasSeedAddress else { return }
        Task {
            let placemarks = try? await geocoder.reverseGeocodeLocation(location)
            currentAddress = placemarks?.first.flatMap { placemark in
                [placemark.name, placemark.locality, placemark.administrativeArea]
                    .compactMap { $0 }
                    .joined(separator: ", ")
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationError = CaptureLocationErrorPresenter.message(for: error)
    }
}

extension CaptureFlowViewModel {
    struct UploadStatus: Identifiable, Equatable {
        var metadata: CaptureUploadMetadata
        let packageURL: URL
        var state: State
        var targetName: String?
        var estimatedPayoutRange: ClosedRange<Int>?

        var id: UUID { metadata.id }

        enum State: Equatable {
            case queued
            case uploading(progress: Double)
            case completed
            case failed(message: String)
        }

        init(request: CaptureUploadRequest, targetName: String? = nil, estimatedPayoutRange: ClosedRange<Int>? = nil) {
            self.metadata = request.metadata
            self.packageURL = request.packageURL
            self.state = .queued
            self.targetName = targetName
            self.estimatedPayoutRange = estimatedPayoutRange
        }
    }
}

struct AddressResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let completionTitle: String
    let completionSubtitle: String
    let placeId: String?
    let formattedAddress: String?
    let lat: Double?
    let lng: Double?
    let accuracyM: Double?
    let placeTypes: [String]
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension CaptureUploadMetadata {
    func applyingCaptureNotes(_ rawNotes: String) -> CaptureUploadMetadata {
        let trimmed = rawNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteItems = trimmed.isEmpty ? [] : [trimmed]
        let updatedSceneMemory = SceneMemoryCaptureMetadata(
            continuityScore: sceneMemory?.continuityScore,
            lightingConsistency: sceneMemory?.lightingConsistency,
            dynamicObjectDensity: sceneMemory?.dynamicObjectDensity,
            operatorNotes: noteItems,
            inaccessibleAreas: sceneMemory?.inaccessibleAreas ?? [],
            semanticAnchorsObserved: sceneMemory?.semanticAnchorsObserved ?? [],
            relocalizationCount: sceneMemory?.relocalizationCount,
            overlapCheckpointCount: sceneMemory?.overlapCheckpointCount
        )
        let baseParts = (captureContextHint ?? "")
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Notes: ") }
        let updatedHint = (baseParts + (trimmed.isEmpty ? [] : ["Notes: \(trimmed)"]))
            .joined(separator: " | ")
            .nilIfEmpty

        return CaptureUploadMetadata(
            id: id,
            targetId: targetId,
            reservationId: reservationId,
            jobId: jobId,
            captureJobId: captureJobId,
            buyerRequestId: buyerRequestId,
            siteSubmissionId: siteSubmissionId,
            regionId: regionId,
            creatorId: creatorId,
            capturedAt: capturedAt,
            uploadedAt: uploadedAt,
            captureSource: captureSource,
            specialTaskType: specialTaskType,
            priorityWeight: priorityWeight,
            quotedPayoutCents: quotedPayoutCents,
            rightsProfile: rightsProfile,
            requestedOutputs: requestedOutputs,
            intakePacket: intakePacket,
            intakeMetadata: intakeMetadata,
            taskHypothesis: taskHypothesis,
            scaffoldingPacket: scaffoldingPacket,
            captureModality: captureModality,
            evidenceTier: evidenceTier,
            captureContextHint: updatedHint,
            sceneMemory: updatedSceneMemory,
            captureRights: captureRights,
            siteIdentity: siteIdentity,
            captureTopology: captureTopology,
            captureMode: captureMode,
            semanticAnchors: semanticAnchors
        )
    }
}
