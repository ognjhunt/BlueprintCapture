import Foundation
import Combine
import CoreLocation
import AVFoundation
import CoreMotion
import MapKit

@MainActor
final class CaptureFlowViewModel: NSObject, ObservableObject {
    enum Step {
        case collectProfile
        case defineSubmission
        case confirmLocation
        case requestPermissions
        case reviewCapture
        case readyToCapture
        case captureSummary
    }

    @Published var profile: UserProfile = .placeholder
    @Published var step: Step = .collectProfile
    @Published var currentAddress: String?
    @Published var locationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationError: String?
    @Published var cameraAuthorized = false
    @Published var microphoneAuthorized = false
    @Published var motionAuthorized = false
    @Published var addressSearchResults: [AddressResult] = []
    @Published var isSearchingAddress = false
    @Published var submissionDraft = SiteSubmissionDraft()
    @Published var captureChecklist = TaskCaptureContext.defaultChecklist()
    @Published var evidenceCoverageDeclarations = TaskCaptureContext.defaultCoverageDeclarations()
    @Published private(set) var activeCaptureContext: TaskCaptureContext?
    @Published private(set) var latestCompletedCaptureContext: TaskCaptureContext?
    @Published private(set) var uploadStatuses: [UploadStatus] = []

    let locationManager = CLLocationManager()
    let captureManager = VideoCaptureManager()

    private let geocoder = CLGeocoder()
    private let placesAutocomplete: PlacesAutocompleteServiceProtocol = PlacesAutocompleteService()
    private let placesDetails: PlacesDetailsServiceProtocol = PlacesDetailsService()
    private let motionManager = CMMotionActivityManager()
    private let uploadService: CaptureUploadServiceProtocol
    private let pipelineBridge: CapturePipelineBridgeProtocol
    private var placesSessionToken: String?
    private var hasRequestedPermissions = false
    private var uploadStatusMap: [UUID: UploadStatus] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var searchDebounceTask: Task<Void, Never>?
    private var currentSearchQuery = ""

    init(
        uploadService: CaptureUploadServiceProtocol = CaptureUploadService(),
        pipelineBridge: CapturePipelineBridgeProtocol = CapturePipelineBridge()
    ) {
        self.uploadService = uploadService
        self.pipelineBridge = pipelineBridge
        super.init()
        locationManager.delegate = self
        cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let audioSession = AVAudioSession.sharedInstance()
        microphoneAuthorized = audioSession.recordPermission == .granted
        if CMMotionActivityManager.isActivityAvailable() {
            motionAuthorized = CMMotionActivityManager.authorizationStatus() == .authorized
        } else {
            motionAuthorized = true
        }
        observeUploadEvents()
    }

    var canContinueFromIntake: Bool {
        submissionDraft.canCreateSubmission
    }

    var canReviewCapture: Bool {
        canContinueFromIntake && !(resolvedSiteLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var canStartCapture: Bool {
        guard let context = pendingCaptureContext() else { return false }
        return context.isReadyForCapture
    }

    private var resolvedSiteLocation: String {
        let current = currentAddress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !current.isEmpty {
            return current
        }
        return submissionDraft.siteLocation.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func loadProfile() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        profile = .sample
    }

    func continueFromProfile() {
        step = .defineSubmission
    }

    func continueFromIntake() {
        step = .confirmLocation
        requestCurrentLocationIfPossible()
    }

    func confirmAddress() {
        submissionDraft.syncSiteLocation(currentAddress)
        guard canReviewCapture else { return }
        if cameraAuthorized, microphoneAuthorized {
            step = .reviewCapture
        } else {
            step = .requestPermissions
        }
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

    func beginCapture() {
        submissionDraft.syncSiteLocation(currentAddress)
        guard let context = pendingCaptureContext(), context.isReadyForCapture else { return }
        activeCaptureContext = context
        captureManager.configureCaptureContext(context)
        step = .readyToCapture
    }

    func cancelActiveCapture() {
        captureManager.stopRecording()
        captureManager.stopSession()
        captureManager.configureCaptureContext(nil)
        activeCaptureContext = nil
        step = .reviewCapture
    }

    func prepareAnotherCapturePass() {
        activeCaptureContext = nil
        captureManager.configureCaptureContext(nil)
        step = .reviewCapture
    }

    func handleRecordingFinished(artifacts: VideoCaptureManager.RecordingArtifacts) {
        guard let activeCaptureContext else { return }
        let metadata = CaptureUploadMetadata(
            id: UUID(),
            submissionId: activeCaptureContext.submissionId,
            siteId: activeCaptureContext.siteId,
            taskId: activeCaptureContext.taskId,
            capturePassId: activeCaptureContext.capturePass.capturePassId,
            creatorId: profile.id.uuidString,
            capturedAt: artifacts.startedAt,
            uploadedAt: nil
        )
        do {
            let stagedOutput = try pipelineBridge.stageArtifacts(
                for: activeCaptureContext,
                recording: artifacts,
                requestedLanesOverride: nil
            )
            let request = CaptureUploadRequest(
                packageURL: artifacts.packageURL,
                metadata: metadata,
                artifacts: stagedOutput.artifacts
            )
            uploadService.enqueue(request)
        } catch {
            uploadStatusMap[metadata.id] = UploadStatus(
                metadata: metadata,
                packageURL: artifacts.packageURL,
                state: .failed(message: error.localizedDescription)
            )
            refreshUploadStatuses()
        }
        latestCompletedCaptureContext = activeCaptureContext
        step = .captureSummary
    }

    func retryUpload(id: UUID) {
        uploadService.retryUpload(id: id)
    }

    func dismissUpload(id: UUID) {
        uploadStatusMap.removeValue(forKey: id)
        refreshUploadStatuses()
    }

    func searchAddresses(query: String) async {
        searchDebounceTask?.cancel()
        currentSearchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= 3 else {
            await MainActor.run {
                self.addressSearchResults = []
                self.isSearchingAddress = false
            }
            placesSessionToken = nil
            return
        }

        await MainActor.run { self.isSearchingAddress = true }

        searchDebounceTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await performAddressSearch(query: trimmed)
            } catch {
                print("🔍 [Autocomplete] Search task cancelled")
            }
        }
    }

    func selectAddress(_ result: AddressResult) {
        currentAddress = "\(result.title), \(result.subtitle)"
        submissionDraft.syncSiteLocation(currentAddress)
        addressSearchResults = []
        placesSessionToken = nil
    }

    private func requestCurrentLocationIfPossible() {
        guard CLLocationManager.locationServicesEnabled() else {
            locationError = "Location services are disabled. Enable them in Settings to continue."
            return
        }
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
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
        guard CMMotionActivityManager.isActivityAvailable() else {
            await MainActor.run { motionAuthorized = true }
            return
        }

        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized:
            await MainActor.run { motionAuthorized = true }
        case .denied, .restricted:
            await MainActor.run { motionAuthorized = false }
        case .notDetermined:
            let start = Date().addingTimeInterval(-60)
            try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                motionManager.queryActivityStarting(from: start, to: Date(), to: OperationQueue.main) { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            await MainActor.run {
                motionAuthorized = CMMotionActivityManager.authorizationStatus() == .authorized
            }
        @unknown default:
            await MainActor.run { motionAuthorized = false }
        }
    }

    private func evaluatePermissions() {
        if cameraAuthorized && microphoneAuthorized {
            step = .reviewCapture
        }
    }

    private func pendingCaptureContext() -> TaskCaptureContext? {
        submissionDraft.syncSiteLocation(currentAddress)
        let context = submissionDraft.makeTaskCaptureContext(
            checklist: captureChecklist,
            coverage: evidenceCoverageDeclarations
        )
        return context
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
            uploadStatusMap[request.metadata.id] = UploadStatus(request: request)
        case .progress(let id, let progress):
            guard var status = uploadStatusMap[id] else { break }
            status.state = .uploading(progress: progress)
            uploadStatusMap[id] = status
        case .completed(let request):
            guard var status = uploadStatusMap[request.metadata.id] else { break }
            status.metadata = request.metadata
            status.state = .completed
            uploadStatusMap[request.metadata.id] = status
        case .failed(let request, let error):
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

    private func performAddressSearch(query: String) async {
        if placesSessionToken == nil {
            placesSessionToken = UUID().uuidString
        }

        guard query == currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else {
            await MainActor.run { self.isSearchingAddress = false }
            return
        }

        defer {
            Task { @MainActor in
                self.isSearchingAddress = false
            }
        }

        if AppConfig.placesAPIKey() != nil {
            do {
                let suggestions = try await placesAutocomplete.autocomplete(
                    input: query,
                    sessionToken: placesSessionToken ?? UUID().uuidString,
                    origin: nil,
                    radiusMeters: nil
                )

                guard query == currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                guard !suggestions.isEmpty else {
                    throw NSError(domain: "AutocompleteError", code: -1, userInfo: nil)
                }

                let details = try await placesDetails.fetchDetails(placeIds: suggestions.map { $0.placeId })
                guard query == currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }

                let byId = Dictionary(uniqueKeysWithValues: details.map { ($0.placeId, $0) })
                let mapped: [AddressResult] = suggestions.compactMap { suggestion in
                    let detail = byId[suggestion.placeId]
                    let title = suggestion.primaryText
                    let subtitle = suggestion.secondaryText.isEmpty ? (detail?.formattedAddress ?? "") : suggestion.secondaryText
                    return AddressResult(
                        title: title,
                        subtitle: subtitle,
                        completionTitle: title,
                        completionSubtitle: subtitle
                    )
                }
                await MainActor.run { self.addressSearchResults = Array(mapped.prefix(5)) }
                return
            } catch {
                print("❌ [Autocomplete] Error: \(error.localizedDescription)")
            }
        }

        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = query
        let search = MKLocalSearch(request: searchRequest)
        do {
            let response = try await search.start()
            guard query == currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }

            let results = response.mapItems.prefix(5).map { mapItem in
                AddressResult(
                    title: mapItem.name ?? "Unknown",
                    subtitle: mapItem.placemark.locality ?? mapItem.placemark.administrativeArea ?? "",
                    completionTitle: mapItem.name ?? "Unknown",
                    completionSubtitle: mapItem.placemark.locality ?? mapItem.placemark.administrativeArea ?? ""
                )
            }
            await MainActor.run { self.addressSearchResults = Array(results) }
        } catch {
            await MainActor.run { self.addressSearchResults = [] }
        }
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
        Task {
            let placemarks = try? await geocoder.reverseGeocodeLocation(location)
            await MainActor.run {
                currentAddress = placemarks?.first.flatMap { placemark in
                    [placemark.name, placemark.locality, placemark.administrativeArea]
                        .compactMap { $0 }
                        .joined(separator: ", ")
                }
                submissionDraft.syncSiteLocation(currentAddress)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationError = error.localizedDescription
    }
}

extension CaptureFlowViewModel {
    struct UploadStatus: Identifiable, Equatable {
        var metadata: CaptureUploadMetadata
        let packageURL: URL
        var state: State

        var id: UUID { metadata.id }

        enum State: Equatable {
            case queued
            case uploading(progress: Double)
            case completed
            case failed(message: String)
        }

        init(request: CaptureUploadRequest) {
            self.metadata = request.metadata
            self.packageURL = request.packageURL
            self.state = .queued
        }

        init(metadata: CaptureUploadMetadata, packageURL: URL, state: State) {
            self.metadata = metadata
            self.packageURL = packageURL
            self.state = state
        }
    }
}

struct AddressResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let completionTitle: String
    let completionSubtitle: String
}
