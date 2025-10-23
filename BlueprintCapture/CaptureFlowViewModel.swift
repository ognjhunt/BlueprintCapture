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
    private let motionManager = CMMotionActivityManager()
    let captureManager = VideoCaptureManager()

    private var hasRequestedPermissions = false
    private let onboardingKey = "com.blueprint.isOnboarded"
    private let uploadService: CaptureUploadServiceProtocol
    private var uploadStatusMap: [UUID: UploadStatus] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init(uploadService: CaptureUploadServiceProtocol = CaptureUploadService()) {
        self.uploadService = uploadService
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

    func searchAddresses(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            addressSearchResults = []
            return
        }
        
        isSearchingAddress = true
        defer { isSearchingAddress = false }
        
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = query
        
        let search = MKLocalSearch(request: searchRequest)
        
        do {
            let response = try await search.start()
            await MainActor.run {
                self.addressSearchResults = response.mapItems.prefix(5).map { mapItem in
                    let title = mapItem.name ?? "Unknown"
                    let subtitle = mapItem.placemark.locality ?? mapItem.placemark.administrativeArea ?? ""
                    return AddressResult(
                        title: title,
                        subtitle: subtitle,
                        completionTitle: title,
                        completionSubtitle: subtitle
                    )
                }
            }
        } catch {
            await MainActor.run {
                self.addressSearchResults = []
            }
        }
    }
    
    func selectAddress(_ result: AddressResult) {
        currentAddress = "\(result.title), \(result.subtitle)"
        addressSearchResults = []
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
