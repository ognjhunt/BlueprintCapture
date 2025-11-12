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
        case confirmLocation
        case requestPermissions
        case readyToCapture
    }

    @Published var profile: UserProfile = .placeholder
    @Published var step: Step = .collectProfile
    @Published var isOnboarded: Bool = false
    @Published var currentAddress: String?
    @Published var locationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationError: String?
    @Published var cameraAuthorized = false
    @Published var microphoneAuthorized = false
    @Published var motionAuthorized = false
    @Published var addressSearchResults: [AddressResult] = []
    @Published var isSearchingAddress = false
    @Published private(set) var uploadStatuses: [UploadStatus] = []

    let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    // Google Places
    private let placesAutocomplete: PlacesAutocompleteServiceProtocol = PlacesAutocompleteService()
    private let placesDetails: PlacesDetailsServiceProtocol = PlacesDetailsService()
    private var placesSessionToken: String?
    private let motionManager = CMMotionActivityManager()
    let roomPlanManager: RoomPlanCaptureManaging
    let captureManager: VideoCaptureManager

    private var hasRequestedPermissions = false
    private let onboardingKey = "com.blueprint.isOnboarded"
    private let uploadService: CaptureUploadServiceProtocol
    private let targetStateService: TargetStateServiceProtocol
    private var uploadStatusMap: [UUID: UploadStatus] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var searchDebounceTask: Task<Void, Never>?
    private var currentSearchQuery: String = ""

    init(uploadService: CaptureUploadServiceProtocol = CaptureUploadService(),
         targetStateService: TargetStateServiceProtocol = TargetStateService(),
         roomPlanManager: RoomPlanCaptureManaging = RoomPlanCaptureManagerFactory.makeManager()) {
        self.uploadService = uploadService
        self.targetStateService = targetStateService
        self.roomPlanManager = roomPlanManager
        self.captureManager = VideoCaptureManager(roomPlanManager: roomPlanManager)
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

        // Check if user has already completed onboarding
        isOnboarded = UserDefaults.standard.bool(forKey: onboardingKey)

        observeUploadEvents()
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
        
        if AppConfig.placesAPIKey() != nil {
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
                        completionSubtitle: subtitle
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
                    completionSubtitle: subtitle
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
        currentAddress = "\(result.title), \(result.subtitle)"
        addressSearchResults = []
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
        let jobId = reservationId ?? targetId ?? UUID().uuidString
        let metadata = CaptureUploadMetadata(
            id: UUID(),
            targetId: targetId,
            reservationId: reservationId,
            jobId: jobId,
            creatorId: profile.id.uuidString,
            capturedAt: Date(),
            uploadedAt: nil
        )
        let request = CaptureUploadRequest(packageURL: artifacts.packageURL, metadata: metadata)
        print("📦 [CaptureFlowViewModel] Enqueuing upload jobId=\(jobId) id=\(metadata.id)")
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
            uploadStatusMap[request.metadata.id] = UploadStatus(request: request)
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
    }
}

struct AddressResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let completionTitle: String
    let completionSubtitle: String
}
