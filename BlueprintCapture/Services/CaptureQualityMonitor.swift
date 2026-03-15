import Foundation
import ARKit
import CoreMotion
import Combine

@MainActor
final class CaptureQualityMonitor: ObservableObject {

    enum SteadinessLevel: String {
        case good, fair, poor

        var color: String {
            switch self {
            case .good: return "green"
            case .fair: return "yellow"
            case .poor: return "red"
            }
        }

        var label: String {
            switch self {
            case .good: return "Steady"
            case .fair: return "Moderate"
            case .poor: return "Too shaky"
            }
        }
    }

    enum TrackingQuality {
        case normal
        case limited(ARCamera.TrackingState.Reason?)
        case notAvailable

        var isGood: Bool {
            if case .normal = self { return true }
            return false
        }

        var warningMessage: String? {
            switch self {
            case .normal: return nil
            case .notAvailable: return "Tracking lost — hold still"
            case .limited(let reason):
                switch reason {
                case .initializing: return "Initializing tracking..."
                case .excessiveMotion: return "Slow down — too much motion"
                case .insufficientFeatures: return "Not enough visual features"
                case .relocalizing: return "Re-establishing position..."
                case .none: return "Tracking limited"
                @unknown default: return "Tracking limited"
                }
            }
        }
    }

    @Published private(set) var trackingQuality: TrackingQuality = .notAvailable
    @Published private(set) var meshAnchorCount: Int = 0
    @Published private(set) var steadiness: SteadinessLevel = .good
    @Published private(set) var hasLiDAR: Bool = false
    @Published private(set) var frameCount: Int = 0
    @Published private(set) var depthFrameCount: Int = 0
    @Published private(set) var estimatedDataSizeMB: Double = 0
    @Published private(set) var elapsedSeconds: TimeInterval = 0

    private var startDate: Date?
    private var timer: Timer?
    private var gyroSamples: [Double] = []
    private let gyroWindowSize = 100 // ~1 second at 100Hz
    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.blueprint.quality.motion"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private var previousSteadiness: SteadinessLevel?

    init() {
        self.hasLiDAR = DeviceCapabilityService.shared.hasLiDAR
    }

    func start() {
        startDate = Date()
        frameCount = 0
        depthFrameCount = 0
        meshAnchorCount = 0
        estimatedDataSizeMB = 0
        elapsedSeconds = 0
        gyroSamples = []
        steadiness = .good
        trackingQuality = .notAvailable
        previousSteadiness = nil

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.startDate else { return }
                self.elapsedSeconds = Date().timeIntervalSince(start)
            }
        }

        startMotionUpdates()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        motionManager.stopGyroUpdates()
    }

    // MARK: - ARSession Updates

    nonisolated func updateFromARFrame(_ frame: ARFrame) {
        let hasDepth = frame.sceneDepth != nil || frame.smoothedSceneDepth != nil
        let tracking: TrackingQuality
        switch frame.camera.trackingState {
        case .normal:
            tracking = .normal
        case .limited(let reason):
            tracking = .limited(reason)
        case .notAvailable:
            tracking = .notAvailable
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.frameCount += 1
            if hasDepth { self.depthFrameCount += 1 }
            self.trackingQuality = tracking

            // Rough data size estimate: ~50KB per RGB frame + ~20KB per depth frame
            self.estimatedDataSizeMB = (Double(self.frameCount) * 0.05 + Double(self.depthFrameCount) * 0.02)
        }
    }

    nonisolated func updateMeshAnchorCount(_ count: Int) {
        Task { @MainActor [weak self] in
            self?.meshAnchorCount = count
        }
    }

    // MARK: - Steadiness

    private func startMotionUpdates() {
        guard motionManager.isGyroAvailable else { return }
        motionManager.gyroUpdateInterval = 0.01 // 100Hz
        motionManager.startGyroUpdates(to: motionQueue) { [weak self] data, _ in
            guard let data else { return }
            let magnitude = sqrt(
                data.rotationRate.x * data.rotationRate.x +
                data.rotationRate.y * data.rotationRate.y +
                data.rotationRate.z * data.rotationRate.z
            )
            Task { @MainActor [weak self] in
                self?.addGyroSample(magnitude)
            }
        }
    }

    private func addGyroSample(_ magnitude: Double) {
        gyroSamples.append(magnitude)
        if gyroSamples.count > gyroWindowSize {
            gyroSamples.removeFirst(gyroSamples.count - gyroWindowSize)
        }

        guard gyroSamples.count >= 20 else { return }

        let mean = gyroSamples.reduce(0, +) / Double(gyroSamples.count)
        let variance = gyroSamples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(gyroSamples.count)
        let stdDev = sqrt(variance)

        let newLevel: SteadinessLevel
        if stdDev < 0.5 {
            newLevel = .good
        } else if stdDev < 1.5 {
            newLevel = .fair
        } else {
            newLevel = .poor
        }

        if newLevel != steadiness {
            steadiness = newLevel
        }
    }

    /// Formatted elapsed time as MM:SS
    var elapsedFormatted: String {
        let mins = Int(elapsedSeconds) / 60
        let secs = Int(elapsedSeconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    /// Formatted data size
    var dataSizeFormatted: String {
        if estimatedDataSizeMB < 1.0 {
            return String(format: "%.0f KB", estimatedDataSizeMB * 1024)
        }
        if estimatedDataSizeMB < 1024 {
            return String(format: "%.1f MB", estimatedDataSizeMB)
        }
        return String(format: "%.1f GB", estimatedDataSizeMB / 1024)
    }

    /// Coverage estimate based on mesh anchor count (rough heuristic)
    var estimatedCoveragePercent: Double {
        // Each mesh anchor covers roughly 1-2 sq meters.
        // A typical space is 50-200 sq meters. Use 100 as baseline.
        let estimatedArea = Double(meshAnchorCount) * 1.5
        let targetArea = 100.0
        return min(100.0, (estimatedArea / targetArea) * 100.0)
    }
}
