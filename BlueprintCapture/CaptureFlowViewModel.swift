import Foundation
import CoreLocation
import AVFoundation
import CoreMotion

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
    @Published var currentAddress: String?
    @Published var locationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationError: String?
    @Published var cameraAuthorized = false
    @Published var microphoneAuthorized = false
    @Published var motionAuthorized = false

    let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let motionManager = CMMotionActivityManager()
    let captureManager = VideoCaptureManager()

    private var hasRequestedPermissions = false

    override init() {
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
    }

    func loadProfile() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        profile = .sample
    }

    func requestLocation() {
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
