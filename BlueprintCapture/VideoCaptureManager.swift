import Foundation
import ARKit
import AVFoundation
import Combine
import CoreMotion
import CoreMedia
import Metal
import UniformTypeIdentifiers
import UIKit
import ImageIO
import ReplayKit
import Darwin
#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

@MainActor
final class VideoCaptureManager: NSObject, ObservableObject {
    enum CaptureState {
        case idle
        case recording(RecordingArtifacts)
        case finished(RecordingArtifacts)
        case error(String)
    }

    struct RecordingArtifacts: Equatable {
        struct ARKitArtifacts: Equatable {
            let rootDirectoryURL: URL
            let frameLogURL: URL
            let depthDirectoryURL: URL?
            let confidenceDirectoryURL: URL?
            let meshDirectoryURL: URL?
            let posesLogURL: URL
            let intrinsicsURL: URL
            let featurePointsLogURL: URL
            let planeObservationsLogURL: URL
            let lightEstimatesLogURL: URL
        }

        let baseFilename: String
        let directoryURL: URL
        let videoURL: URL
        let motionLogURL: URL
        let manifestURL: URL
        let arKit: ARKitArtifacts?
        let packageURL: URL
        let startedAt: Date

        var shareItems: [Any] {
            var items: [Any] = [packageURL, videoURL, motionLogURL, manifestURL]
            if let arKit {
                items.append(arKit.frameLogURL)
            }
            return items
        }

        var uploadPayload: CaptureUploadPayload {
            CaptureUploadPayload(packageURL: packageURL)
        }
    }

    struct CaptureUploadPayload: Codable, Equatable {
        let packageURL: URL
    }

    struct EntryAnchorHold: Equatable {
        let anchorId: String            // always "anchor_entry" (v1)
        let holdStartFrameId: String    // frameId of first frame in hold window
        let holdEndFrameId: String      // frameId when 2 s threshold was met
        let tCaptureSec: Double         // midpoint t_device_sec of the hold
        let durationSec: Double         // total hold duration in seconds
    }

    struct RecordingSessionMetadata: Equatable, Codable {
        let schemaVersion: String
        let coordinateFrameSessionId: String
        let startedAt: Date
        let captureSource: String

        init(
            schemaVersion: String = "v1",
            coordinateFrameSessionId: String,
            startedAt: Date,
            captureSource: String = VideoCaptureManager.captureSource
        ) {
            self.schemaVersion = schemaVersion
            self.coordinateFrameSessionId = coordinateFrameSessionId
            self.startedAt = startedAt
            self.captureSource = captureSource
        }
    }

    private struct ARFrameLogEntry: Codable {
        let frameId: String
        let frameIndex: Int
        let timestamp: TimeInterval
        let tCaptureSec: Double
        let tMonotonicNs: Int64
        let capturedAt: Date
        let cameraTransform: [Float]
        let intrinsics: [Float]
        let imageResolution: [Int]
        let depthSource: String?
        let sceneDepthFile: String?
        let smoothedSceneDepthFile: String?
        let confidenceFile: String?
        let depthValidFraction: Double?
        let missingDepthFraction: Double?
        // Tracking health
        let trackingState: String
        let trackingReason: String?
        let worldMappingStatus: String?
        let relocalizationEvent: Bool
        // Exposure quality
        let exposureDurationS: Double?
        let iso: Double?
        let exposureTargetBias: Float?
        let whiteBalanceGains: CaptureManifest.WhiteBalanceGains?
        // Image sharpness (higher = sharper; computed from luma variance)
        let sharpnessScore: Double?
        // Anchor observations populated in Phase 2 when structured routes are active
        let anchorObservations: [String]
        let coordinateFrameSessionId: String?
    }

    private struct ARFeaturePointLogEntry: Codable {
        let frameId: String
        let tCaptureSec: Double
        let tMonotonicNs: Int64
        let rawPointCount: Int
        let sampledWorldPoints: [[Float]]
        let coordinateFrameSessionId: String?
    }

    private struct ARPlaneObservationLogEntry: Codable {
        let frameId: String
        let tCaptureSec: Double
        let tMonotonicNs: Int64
        let anchorId: String
        let alignment: String
        let classification: String?
        let center: [Float]
        let extent: [Float]
        let transform: [Float]
        let coordinateFrameSessionId: String?
    }

    private struct ARLightEstimateLogEntry: Codable {
        let frameId: String
        let tCaptureSec: Double
        let tMonotonicNs: Int64
        let ambientIntensity: Double?
        let ambientColorTemperature: Double?
        let coordinateFrameSessionId: String?
    }

    struct PipelinePoseRow: Codable {
        let pose_schema_version: String
        let frameIndex: Int
        let timestamp: Double
        let transform: [[Double]]
        let frame_id: String
        let t_device_sec: Double
        let t_monotonic_ns: Int64
        let T_world_camera: [[Double]]
        let tracking_state: String
        let tracking_reason: String?
        let world_mapping_status: String?
        let coordinate_frame_session_id: String?

        enum CodingKeys: String, CodingKey {
            case pose_schema_version
            case frameIndex = "frame_index"
            case timestamp
            case transform
            case frame_id
            case t_device_sec
            case t_monotonic_ns
            case T_world_camera
            case tracking_state
            case tracking_reason
            case world_mapping_status
            case coordinate_frame_session_id
        }
    }

    static let poseSchemaVersion = "3.0"
    static let captureSchemaVersion = "3.1.0"
    static let captureSource = "iphone"
    static let captureTierHint = "tier1_iphone"
    static let movingDepthSnapshotIntervalSeconds: TimeInterval = 0.2
    static let stationaryDepthSnapshotIntervalSeconds: TimeInterval = 1.0
    static let minimumDepthTravelMeters: Float = 0.05

    nonisolated static func deviceTimeSeconds(frameTimestamp: TimeInterval, firstFrameTimestamp: TimeInterval?) -> Double {
        let base = firstFrameTimestamp ?? frameTimestamp
        return max(0.0, frameTimestamp - base)
    }

    static func monotonicNanoseconds(from timestamp: TimeInterval) -> Int64 {
        Int64((timestamp * 1_000_000_000.0).rounded())
    }

    static func sampledFeaturePoints(from frame: ARFrame, limit: Int = 128) -> [simd_float3] {
        guard let rawFeaturePoints = frame.rawFeaturePoints, rawFeaturePoints.points.count > 0 else {
            return []
        }
        let points = rawFeaturePoints.points
        guard points.count > limit else { return Array(points) }
        let stride = max(1, points.count / limit)
        var sampled: [simd_float3] = []
        sampled.reserveCapacity(limit)
        var index = 0
        while index < points.count, sampled.count < limit {
            sampled.append(points[index])
            index += stride
        }
        return sampled
    }

    /// Estimates image sharpness via Laplacian variance on a downsampled luma plane.
    /// Operates on a 64×64 thumbnail to keep per-frame CPU overhead low.
    /// Higher score = sharper image. Returns nil if the pixel buffer cannot be accessed.
    static func laplacianVariance(pixelBuffer: CVPixelBuffer, thumbnailSize: Int = 64) -> Double? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0,
              let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return nil
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let lumaBytes = baseAddress.assumingMemoryBound(to: UInt8.self)

        // Sample a sparse grid of pixels at thumbnail_size × thumbnail_size spacing.
        let stepX = max(1, width / thumbnailSize)
        let stepY = max(1, height / thumbnailSize)
        var sum: Double = 0
        var sumSq: Double = 0
        var count: Int = 0

        var y = stepY
        while y < height - stepY {
            var x = stepX
            while x < width - stepX {
                let center = Double(lumaBytes[y * bytesPerRow + x])
                let top    = Double(lumaBytes[(y - stepY) * bytesPerRow + x])
                let bottom = Double(lumaBytes[(y + stepY) * bytesPerRow + x])
                let left   = Double(lumaBytes[y * bytesPerRow + (x - stepX)])
                let right  = Double(lumaBytes[y * bytesPerRow + (x + stepX)])
                let laplacian = 4 * center - top - bottom - left - right
                sum += laplacian
                sumSq += laplacian * laplacian
                count += 1
                x += stepX
            }
            y += stepY
        }

        guard count > 0 else { return nil }
        let mean = sum / Double(count)
        let variance = (sumSq / Double(count)) - mean * mean
        return max(0, variance)
    }

    @Published private(set) var captureState: CaptureState = .idle
    @Published private(set) var latestUploadPayload: CaptureUploadPayload?
    let qualityMonitor = CaptureQualityMonitor()

    let session = AVCaptureSession()
    let arSession = ARSession()

    /// Returns true when the capture manager will use ARSession for video recording.
    /// When true, the UI should use ARView instead of AVCaptureVideoPreviewLayer for camera preview.
    var usesARSessionForCapture: Bool {
        canUseARSessionRecorder
    }

    var latestRecordingSessionId: String? {
        latestRecordingSession?.coordinateFrameSessionId
    }

    var latestRecordingStartedAt: Date? {
        latestRecordingSession?.startedAt
    }

    private let movieOutput = AVCaptureMovieFileOutput()
    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.blueprint.capture.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private let motionLogQueue = DispatchQueue(label: "com.blueprint.capture.motionlog")
    private let manifestQueue = DispatchQueue(label: "com.blueprint.capture.manifest")
    private let arDataQueue = DispatchQueue(label: "com.blueprint.capture.arkit", qos: .userInitiated)
    private let motionJSONEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
    private let manifestEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return encoder
    }()
    private let arFrameEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    private var videoDevice: AVCaptureDevice?
    private var currentArtifacts: RecordingArtifacts?
    private var motionLogFileHandle: FileHandle?
    private var arFrameLogFileHandle: FileHandle?
    private var arPoseLogFileHandle: FileHandle?
    private var arFeaturePointsLogFileHandle: FileHandle?
    private var arPlaneObservationsLogFileHandle: FileHandle?
    private var arLightEstimatesLogFileHandle: FileHandle?
    private var arIntrinsicsWritten: Bool = false
    private var currentCameraIntrinsics: CaptureManifest.CameraIntrinsics?
    private var currentExposureSettings: CaptureManifest.ExposureSettings?
    private var exposureSamples: [CaptureManifest.ExposureSample] = []
    private var exposureTimer: Timer?
    private var currentARKitArtifacts: RecordingArtifacts.ARKitArtifacts?
    private var arFrameCount: Int = 0
    private var arFirstFrameTimestamp: TimeInterval?
    private var lastDepthSnapshotTimestamp: TimeInterval?
    private var lastDepthSnapshotPosition: simd_float3?
    private var latestARFrameId: String?
    private var latestARFrameTCaptureSec: Double?
    private var currentRecordingSessionId: String?
    private var pendingAnchorObservationExpirations: [String: Double] = [:]
    // Entry anchor hold detection state (reset at startRecording)
    private(set) var detectedEntryAnchorHold: EntryAnchorHold?
    private(set) var semanticAnchorEvents: [CaptureSemanticAnchorEvent] = []
    private(set) var latestRecordingSession: RecordingSessionMetadata?
    private var holdCandidateOrigin: simd_float3?
    private var holdCandidateStartTDeviceSec: Double = 0
    private var holdCandidateStartFrameId: String = ""
    private var exportedMeshAnchors: Set<UUID> = []
    private var isARRunning: Bool = false
    private var shouldSkipARKitOnNextRecording: Bool = false
    private let supportsARCapture: Bool = VideoCaptureManager.evaluateARCaptureSupport()
    private let supportsMeshReconstruction: Bool = VideoCaptureManager.evaluateMeshSupport()
    private let screenRecorder = RPScreenRecorder.shared()
    private var screenRecordingWriter: ScreenRecordingWriter?
    private var usingScreenRecorder = false
    private var screenRecordingStartDate: Date?
    private var screenRecordingStopDate: Date?
    private var screenRecorderStopTimeoutWorkItem: DispatchWorkItem?
    private var awaitingScreenRecorderCompletion = false
    private var lastCaptureUsedScreenRecorder = false
    private var usingCustomARSessionRecorder = false
    private var awaitingFirstARVideoFrame = false
    private var arSessionRecorder: AnyObject?

    override init() {
        super.init()
        arSession.delegate = self
    }


    var needsAVCaptureSession: Bool {
        !shouldUseScreenRecorder && !canUseARSessionRecorder
    }

    private func disableScreenRecorderDueToError(reason: String) {
        guard !screenRecorderPermanentlyDisabled else { return }
        screenRecorderPermanentlyDisabled = true
        shouldSkipARKitOnNextRecording = true
        currentARKitArtifacts = nil
        print("⚠️ [Capture] Disabling screen recorder path — \(reason). Falling back to AVCaptureSession.")
    }

    private var screenRecorderPermanentlyDisabled = false

    private var shouldUseScreenRecorder: Bool { false }

    /// Use ARSession-based video recording on iOS 17+ devices that support ARKit.
    /// This allows ARKit to own the camera for recording video while also capturing
    /// poses, depth, and intrinsics that strengthen the raw evidence bundle.
    private var canUseARSessionRecorder: Bool {
        guard #available(iOS 17.0, *) else { return false }
        return supportsARCapture
    }

    private static func evaluateARCaptureSupport() -> Bool {
#if targetEnvironment(simulator)
        return false
#else
#if targetEnvironment(macCatalyst)
        return false
#else
        if #available(iOS 14.0, *) {
            if ProcessInfo.processInfo.isiOSAppOnMac {
                return false
            }
        }
        guard ARWorldTrackingConfiguration.isSupported else { return false }
        guard MTLCreateSystemDefaultDevice() != nil else { return false }
        return true
#endif
#endif
    }

    private static func evaluateMeshSupport() -> Bool {
#if targetEnvironment(simulator)
        return false
#else
#if targetEnvironment(macCatalyst)
        return false
#else
        if #available(iOS 13.4, *) {
            return ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        } else {
            return false
        }
#endif
#endif
    }

    func configureSession() {
        if shouldUseScreenRecorder {
            print("⚙️ [Capture] configureSession skipped — using screen recorder")
            return
        }
        if canUseARSessionRecorder {
            print("⚙️ [Capture] configureSession skipped — using shared ARSession recorder")
            return
        }
        guard session.inputs.isEmpty else { print("⚙️ [Capture] configureSession: inputs already configured (inputs=\(session.inputs.count))"); return }

        session.beginConfiguration()
        session.sessionPreset = .high

        do {
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                throw CaptureError.missingCamera
            }
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            self.videoDevice = videoDevice
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }

            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                }
            }

            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
        } catch {
            print("❌ [Capture] configureSession failed: \(error.localizedDescription)")
            captureState = .error(error.localizedDescription)
        }

        session.commitConfiguration()
        print("✅ [Capture] configureSession complete: inputs=\(session.inputs.count), outputs=\(session.outputs.count)")
    }

    func startSession() {
        if shouldUseScreenRecorder {
            print("ℹ️ [Capture] startSession skipped — using screen recorder")
            return
        }
        if canUseARSessionRecorder {
            print("ℹ️ [Capture] startSession skipped — using shared ARSession recorder")
            return
        }
        guard !session.isRunning else { print("ℹ️ [Capture] startSession ignored — already running"); return }
        DispatchQueue.global(qos: .userInitiated).async {
            print("🎥 [Capture] startRunning() …")
            self.session.startRunning()
            print("🎥 [Capture] session started (isRunning=\(self.session.isRunning))")
        }
    }

    func stopSession() {
        if shouldUseScreenRecorder {
            print("ℹ️ [Capture] stopSession skipped — using screen recorder")
            return
        }
        if canUseARSessionRecorder {
            print("ℹ️ [Capture] stopSession skipped — using shared ARSession recorder")
            return
        }
        guard session.isRunning else { print("ℹ️ [Capture] stopSession ignored — not running"); return }
        print("🛑 [Capture] stopRunning() …")
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.stopRunning()
            print("🛑 [Capture] session stopped (isRunning=\(self.session.isRunning))")
        }
    }

    func startRecording() {
        if shouldUseScreenRecorder {
            guard !usingScreenRecorder else { print("ℹ️ [Capture] startRecording ignored — already recording"); return }
        } else {
            guard !movieOutput.isRecording else { print("ℹ️ [Capture] startRecording ignored — already recording"); return }
        }
        print("⏺️ [Capture] startRecording begin")
        let baseName = "walkthrough-\(UUID().uuidString)"
        let includeARKit = !shouldSkipARKitOnNextRecording && !shouldUseScreenRecorder
        let artifacts: RecordingArtifacts
        do {
            artifacts = try makeRecordingArtifacts(baseName: baseName, includeARKit: includeARKit)
        } catch {
            print("❌ [Capture] Failed to prepare capture workspace: \(error.localizedDescription)")
            captureState = .error("Failed to prepare capture workspace: \(error.localizedDescription)")
            return
        }

        currentArtifacts = artifacts
        currentARKitArtifacts = artifacts.arKit
        let recordingSessionId = UUID().uuidString
        currentRecordingSessionId = recordingSessionId
        latestRecordingSession = RecordingSessionMetadata(
            coordinateFrameSessionId: recordingSessionId,
            startedAt: artifacts.startedAt
        )
        arFrameCount = 0
        arFirstFrameTimestamp = nil
        latestARFrameId = nil
        latestARFrameTCaptureSec = nil
        lastDepthSnapshotPosition = nil
        detectedEntryAnchorHold = nil
        holdCandidateOrigin = nil
        holdCandidateStartTDeviceSec = 0
        holdCandidateStartFrameId = ""
        exportedMeshAnchors.removeAll()
        semanticAnchorEvents = []
        pendingAnchorObservationExpirations = [:]
        latestUploadPayload = nil
        exposureSamples = []
        Task { @MainActor in qualityMonitor.start() }
        if shouldUseScreenRecorder {
            currentCameraIntrinsics = makeScreenIntrinsics()
            currentExposureSettings = nil
            awaitingFirstARVideoFrame = false
        } else if canUseARSessionRecorder {
            currentCameraIntrinsics = nil
            currentExposureSettings = makeARSessionExposureSettings()
            awaitingFirstARVideoFrame = true
        } else {
            currentCameraIntrinsics = videoDevice.map(makeCameraIntrinsics)
            currentExposureSettings = videoDevice.map(makeExposureSettings)
            awaitingFirstARVideoFrame = false
        }
        persistManifest(duration: nil)

        prepareMotionLog(for: artifacts)
        guard motionLogFileHandle != nil else {
            currentArtifacts = nil
            return
        }
        prepareARKitLoggingIfNeeded(for: artifacts)
        startMotionUpdates()
        if !canUseARSessionRecorder {
            startExposureLogging()
        }
        shouldSkipARKitOnNextRecording = false
        lastCaptureUsedScreenRecorder = shouldUseScreenRecorder

        if shouldUseScreenRecorder {
            startScreenRecording(for: artifacts)
        } else if canUseARSessionRecorder {
            startSharedARSessionRecording(for: artifacts)
        } else {
            movieOutput.startRecording(to: artifacts.videoURL, recordingDelegate: self)
            if !includeARKit && supportsARCapture {
                print("⚠️ [AR] AR session startup skipped due to previous camera conflict; manifest will omit AR data.")
            }
            captureState = .recording(artifacts)
            print("⏺️ [Capture] startRecording started → file=\(artifacts.videoURL.lastPathComponent)")
        }
    }

    func stopRecording() {
        if shouldUseScreenRecorder {
            guard usingScreenRecorder else { print("ℹ️ [Capture] stopRecording ignored — not recording"); return }
        } else if usingCustomARSessionRecorder {
            // ARSessionRecorder path - handled below
        } else {
            guard movieOutput.isRecording else { print("ℹ️ [Capture] stopRecording ignored — not recording"); return }
        }
        print("⏹️ [Capture] stopRecording begin")
        Task { @MainActor in qualityMonitor.stop() }
        if shouldUseScreenRecorder {
            stopScreenRecording()
        } else if usingCustomARSessionRecorder {
            finishSharedARSessionRecording()
        } else {
            movieOutput.stopRecording()
        }
        print("⏹️ [Capture] stopRecording requested")
    }

    private func startScreenRecording(for artifacts: RecordingArtifacts) {
        guard screenRecorder.isAvailable else {
            let message = "Screen recording is not available on this device."
            print("❌ [Capture] \(message)")
            disableScreenRecorderDueToError(reason: "screen recorder unavailable")
            DispatchQueue.main.async {
                self.latestUploadPayload = nil
                self.captureState = .error(message)
                self.cleanupAfterRecording()
            }
            return
        }

        let orientation = captureState.currentInterfaceOrientation()
        let outputSize = captureState.screenRecordingOutputSize(for: orientation)

        do {
            screenRecordingWriter = try ScreenRecordingWriter(
                destinationURL: artifacts.videoURL,
                outputSize: outputSize,
                orientation: orientation,
                includeAudio: true
            )
        } catch {
            let message = "Unable to start screen recording: \(error.localizedDescription)"
            print("❌ [Capture] \(message)")
            disableScreenRecorderDueToError(reason: "failed to create screen recorder writer")
            DispatchQueue.main.async {
                self.latestUploadPayload = nil
                self.captureState = .error(message)
                self.cleanupAfterRecording()
            }
            return
        }

        usingScreenRecorder = true
        screenRecordingStartDate = Date()
        screenRecorder.isMicrophoneEnabled = true

        screenRecorder.startCapture(handler: { [weak self] sampleBuffer, type, error in
            guard let self else { return }
            if let error {
                print("❌ [Capture] Screen capture error: \(error.localizedDescription)")
                self.handleScreenRecorderFailure(error)
                return
            }
            self.screenRecordingWriter?.append(sampleBuffer: sampleBuffer, of: type)
        }, completionHandler: { [weak self] error in
            guard let self else { return }
            if let error {
                print("❌ [Capture] Failed to start screen capture: \(error.localizedDescription)")
                self.disableScreenRecorderDueToError(reason: "startCapture failed with error")
                self.handleScreenRecorderFailure(error)
            } else {
                DispatchQueue.main.async {
                    if let artifacts = self.currentArtifacts {
                        self.captureState = .recording(artifacts)
                        print("⏺️ [Capture] screen recording started → file=\(artifacts.videoURL.lastPathComponent)")
                    }
                }
            }
        })
    }

    private func stopScreenRecording() {
        let stopDate = Date()
        screenRecordingStopDate = stopDate
        awaitingScreenRecorderCompletion = true
        scheduleScreenRecorderStopTimeout()
        screenRecorder.stopCapture { [weak self] error in
            guard let self else { return }
            self.screenRecorderStopTimeoutWorkItem?.cancel()
            self.screenRecorderStopTimeoutWorkItem = nil
            guard self.awaitingScreenRecorderCompletion else { return }
            self.awaitingScreenRecorderCompletion = false
            let writer = self.screenRecordingWriter
            self.screenRecordingWriter = nil
            let duration = self.screenRecordingStartDate.map { stopDate.timeIntervalSince($0) }
            self.screenRecordingStartDate = nil
            self.screenRecordingStopDate = nil
            if let writer {
                writer.finish { result in
                    switch result {
                    case .success:
                        self.handleRecordingCompletion(error: error, durationSeconds: duration)
                    case .failure(let writerError):
                        self.handleRecordingCompletion(error: writerError, durationSeconds: duration)
                    }
                }
            } else {
                self.handleRecordingCompletion(error: error, durationSeconds: duration)
            }
        }
    }

    private func startSharedARSessionRecording(for artifacts: RecordingArtifacts) {
        guard #available(iOS 17.0, *) else {
            let message = "AR session video capture requires iOS 17 or newer."
            print("❌ [Capture] \(message)")
            stopMotionUpdates()
            stopExposureLogging()
            stopARSession()
            currentArtifacts = nil
            captureState = .error(message)
            cleanupAfterRecording()
            return
        }

        do {
            let orientation = captureState.currentInterfaceOrientation()
            let recorder = try ARSessionVideoRecorder(
                destinationURL: artifacts.videoURL,
                orientation: orientation
            ) { [weak self] error in
                self?.handleARSessionRecorderError(error)
            }
            arSessionRecorder = recorder
            usingCustomARSessionRecorder = true

            // Start ARSession to begin receiving frames
            startARSessionForRecording()

            captureState = .recording(artifacts)
            print("⏺️ [Capture] startRecording started via shared ARSession → file=\(artifacts.videoURL.lastPathComponent)")
        } catch {
            print("❌ [Capture] Failed to start shared ARSession recorder: \(error.localizedDescription)")
            stopMotionUpdates()
            stopExposureLogging()
            stopARSession()
            currentArtifacts = nil
            usingCustomARSessionRecorder = false
            awaitingFirstARVideoFrame = false
            latestUploadPayload = nil
            captureState = .error("Failed to start recording: \(error.localizedDescription)")
            cleanupAfterRecording()
        }
    }

    private func finishSharedARSessionRecording() {
        awaitingFirstARVideoFrame = false
        guard #available(iOS 17.0, *), let recorder = arSessionRecorder as? ARSessionVideoRecorder else {
            usingCustomARSessionRecorder = false
            arSessionRecorder = nil
            handleRecordingCompletion(error: nil, durationSeconds: nil)
            return
        }

        usingCustomARSessionRecorder = false
        recorder.finishRecording { [weak self] result in
            guard let self else { return }
            self.arSessionRecorder = nil
            switch result {
            case .success(let duration):
                self.handleRecordingCompletion(error: nil, durationSeconds: duration)
            case .failure(let error):
                self.handleRecordingCompletion(error: error, durationSeconds: nil)
            }
        }
    }

    private func handleARSessionRecorderError(_ error: Error) {
        print("❌ [Capture] Shared ARSession recorder error: \(error.localizedDescription)")
        arSessionRecorder = nil
        usingCustomARSessionRecorder = false
        awaitingFirstARVideoFrame = false
        handleRecordingCompletion(error: error, durationSeconds: nil)
    }

    private func appendFrameToARRecorder(pixelBuffer: CVPixelBuffer, timestampSeconds: TimeInterval, resolution: CGSize) {
        guard usingCustomARSessionRecorder else { return }
        guard #available(iOS 17.0, *), let recorder = arSessionRecorder as? ARSessionVideoRecorder else { return }
        recorder.append(pixelBuffer: pixelBuffer, timestampSeconds: timestampSeconds, resolution: resolution)
    }

    private func scheduleScreenRecorderStopTimeout() {
        screenRecorderStopTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.awaitingScreenRecorderCompletion else { return }
            print("⚠️ [Capture] Screen recorder stop timed out — forcing completion")
            self.disableScreenRecorderDueToError(reason: "screen recorder stop timed out")
            self.awaitingScreenRecorderCompletion = false
            self.screenRecorderStopTimeoutWorkItem = nil
            let writer = self.screenRecordingWriter
            self.screenRecordingWriter = nil
            let stopDate = self.screenRecordingStopDate ?? Date()
            self.screenRecordingStopDate = nil
            let duration = self.screenRecordingStartDate.map { stopDate.timeIntervalSince($0) }
            self.screenRecordingStartDate = nil
            if let writer {
                writer.finish { result in
                    switch result {
                    case .success:
                        self.handleRecordingCompletion(error: nil, durationSeconds: duration)
                    case .failure(let writerError):
                        self.handleRecordingCompletion(error: writerError, durationSeconds: duration)
                    }
                }
            } else {
                self.handleRecordingCompletion(error: nil, durationSeconds: duration)
            }
        }
        screenRecorderStopTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
    }

    private func handleScreenRecorderFailure(_ error: Error) {
        screenRecorderStopTimeoutWorkItem?.cancel()
        screenRecorderStopTimeoutWorkItem = nil
        awaitingScreenRecorderCompletion = false
        screenRecordingStopDate = nil
        disableScreenRecorderDueToError(reason: "screen recorder failure: \(error.localizedDescription)")
        if screenRecorder.isRecording {
            screenRecorder.stopCapture { _ in }
        }
        usingScreenRecorder = false
        screenRecordingWriter = nil
        screenRecordingStartDate = nil
        stopMotionUpdates()
        stopExposureLogging()
        stopARSession()
        DispatchQueue.main.async {
            self.latestUploadPayload = nil
            self.captureState = .error(error.localizedDescription)
            self.cleanupAfterRecording()
        }
    }

    private func handleRecordingCompletion(error: Error?, durationSeconds: Double?) {
        print("🔚 [Capture] handleRecordingCompletion(error=\(error?.localizedDescription ?? "nil"), duration=\(durationSeconds.map { String(format: "%.2f", $0) } ?? "nil"))")
        screenRecorderStopTimeoutWorkItem?.cancel()
        screenRecorderStopTimeoutWorkItem = nil
        awaitingScreenRecorderCompletion = false
        screenRecordingStopDate = nil
        stopMotionUpdates()
        stopExposureLogging()
        stopARSession()
        usingScreenRecorder = false

        DispatchQueue.main.async {
            if let error {
                let nsError = error as NSError
                var friendlyMessage = nsError.localizedDescription
                let avError = (error as? AVError) ?? AVError(_nsError: nsError)
                if avError.code == .deviceAlreadyUsedByAnotherSession {
                    self.shouldSkipARKitOnNextRecording = true
                    self.currentARKitArtifacts = nil
                    friendlyMessage = "Recording stopped because the camera was busy. AR capture will be disabled on the next attempt."
                    print("⚠️ [Capture] Camera ownership conflict detected; AR startup will be skipped on the next recording.")
                } else if nsError.domain == RPRecordingErrorDomain || nsError.domain == "RPScreenRecorderErrorDomain" {
                    friendlyMessage = "Screen recording failed: \(nsError.localizedDescription)"
                    self.disableScreenRecorderDueToError(reason: "ReplayKit error domain = \(nsError.domain), code = \(nsError.code)")
                }

                print("❌ [Capture] Recording failed: \(nsError.localizedDescription)")
                self.latestUploadPayload = nil
                self.captureState = .error(friendlyMessage)
                self.cleanupAfterRecording()
                return
            }

            self.persistManifest(duration: durationSeconds, synchronous: true)

            guard self.currentArtifacts != nil else {
                self.latestUploadPayload = nil
                self.captureState = .error("Capture artifacts were unavailable.")
                self.cleanupAfterRecording()
                return
            }

            print("📦 [Capture] Packaging artifacts …")
            DispatchQueue.global(qos: .userInitiated).async {
                var artifactsToPackage: RecordingArtifacts?
                DispatchQueue.main.sync {
                    print("📦 [Capture] Capturing currentArtifacts for packaging")
                    artifactsToPackage = self.currentArtifacts
                }
                guard let artifactsToPackage else {
                    DispatchQueue.main.async {
                        self.latestUploadPayload = nil
                        self.captureState = .error("Capture artifacts were unavailable.")
                        self.cleanupAfterRecording()
                    }
                    return
                }
                do {
                    try self.packageArtifacts(artifactsToPackage)
                    DispatchQueue.main.async {
                        self.latestUploadPayload = artifactsToPackage.uploadPayload
                        self.captureState = .finished(artifactsToPackage)
                        print("✅ [Capture] Packaging complete → \(artifactsToPackage.packageURL.lastPathComponent)")
                        self.cleanupAfterRecording()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.latestUploadPayload = nil
                        self.captureState = .error(error.localizedDescription)
                        print("❌ [Capture] Packaging failed: \(error.localizedDescription)")
                        self.cleanupAfterRecording()
                    }
                }
            }
        }
    }

    private func prepareMotionLog(for artifacts: RecordingArtifacts) {
        do {
            if FileManager.default.fileExists(atPath: artifacts.motionLogURL.path) {
                try FileManager.default.removeItem(at: artifacts.motionLogURL)
            }
            FileManager.default.createFile(atPath: artifacts.motionLogURL.path, contents: nil)
            motionLogFileHandle = try FileHandle(forWritingTo: artifacts.motionLogURL)
        } catch {
            motionLogFileHandle = nil
            captureState = .error("Failed to create motion log: \(error.localizedDescription)")
        }
    }

    private func makeRecordingArtifacts(baseName: String, includeARKit: Bool) throws -> RecordingArtifacts {
        let tempDir = FileManager.default.temporaryDirectory
        let recordingDir = tempDir.appendingPathComponent(baseName, isDirectory: true)
        // Always use directory upload (not ZIP) to ensure manifest.json gets patched
        // with scene_id and video_uri by CaptureUploadService during upload.
        // ZIP uploads skip manifest patching which breaks downstream pipeline.
        let packageURL = recordingDir
        let videoURL = recordingDir.appendingPathComponent("walkthrough.mov")
        let motionURL = recordingDir.appendingPathComponent("motion.jsonl")
        let manifestURL = recordingDir.appendingPathComponent("manifest.json")

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: recordingDir.path) {
            try fileManager.removeItem(at: recordingDir)
        }
        try fileManager.createDirectory(at: recordingDir, withIntermediateDirectories: true)

        let arKitArtifacts = includeARKit ? setupARKitArtifacts(in: recordingDir) : nil

        return RecordingArtifacts(
            baseFilename: baseName,
            directoryURL: recordingDir,
            videoURL: videoURL,
            motionLogURL: motionURL,
            manifestURL: manifestURL,
            arKit: arKitArtifacts,
            packageURL: packageURL,
            startedAt: Date()
        )
    }

    private func setupARKitArtifacts(in directory: URL) -> RecordingArtifacts.ARKitArtifacts? {
        guard supportsARCapture else { return nil }

        let fileManager = FileManager.default
        let root = directory.appendingPathComponent("arkit", isDirectory: true)
        let depth = root.appendingPathComponent("depth", isDirectory: true)
        let confidence = root.appendingPathComponent("confidence", isDirectory: true)
        let mesh = root.appendingPathComponent("meshes", isDirectory: true)
        let frameLog = root.appendingPathComponent("frames.jsonl")
        let posesLog = root.appendingPathComponent("poses.jsonl")
        let intrinsics = root.appendingPathComponent("intrinsics.json")
        let featurePointsLog = root.appendingPathComponent("feature_points.jsonl")
        let planeObservationsLog = root.appendingPathComponent("plane_observations.jsonl")
        let lightEstimatesLog = root.appendingPathComponent("light_estimates.jsonl")

        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: depth, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: confidence, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: mesh, withIntermediateDirectories: true)
            fileManager.createFile(atPath: frameLog.path, contents: nil)
            fileManager.createFile(atPath: posesLog.path, contents: nil)
            fileManager.createFile(atPath: intrinsics.path, contents: nil)
            fileManager.createFile(atPath: featurePointsLog.path, contents: nil)
            fileManager.createFile(atPath: planeObservationsLog.path, contents: nil)
            fileManager.createFile(atPath: lightEstimatesLog.path, contents: nil)
            return RecordingArtifacts.ARKitArtifacts(
                rootDirectoryURL: root,
                frameLogURL: frameLog,
                depthDirectoryURL: depth,
                confidenceDirectoryURL: confidence,
                meshDirectoryURL: mesh,
                posesLogURL: posesLog,
                intrinsicsURL: intrinsics,
                featurePointsLogURL: featurePointsLog,
                planeObservationsLogURL: planeObservationsLog,
                lightEstimatesLogURL: lightEstimatesLog
            )
        } catch {
            print("Failed to set up ARKit capture directories: \(error)")
            return nil
        }
    }

    private func prepareARKitLoggingIfNeeded(for artifacts: RecordingArtifacts) {
        guard let arKit = artifacts.arKit else {
            arFrameLogFileHandle = nil
            arPoseLogFileHandle = nil
            arIntrinsicsWritten = false
            return
        }

        do {
            if !FileManager.default.fileExists(atPath: arKit.frameLogURL.path) {
                FileManager.default.createFile(atPath: arKit.frameLogURL.path, contents: nil)
            }
            arFrameLogFileHandle = try FileHandle(forWritingTo: arKit.frameLogURL)
            if !FileManager.default.fileExists(atPath: arKit.posesLogURL.path) {
                FileManager.default.createFile(atPath: arKit.posesLogURL.path, contents: nil)
            }
            arPoseLogFileHandle = try FileHandle(forWritingTo: arKit.posesLogURL)
            if !FileManager.default.fileExists(atPath: arKit.featurePointsLogURL.path) {
                FileManager.default.createFile(atPath: arKit.featurePointsLogURL.path, contents: nil)
            }
            arFeaturePointsLogFileHandle = try FileHandle(forWritingTo: arKit.featurePointsLogURL)
            if !FileManager.default.fileExists(atPath: arKit.planeObservationsLogURL.path) {
                FileManager.default.createFile(atPath: arKit.planeObservationsLogURL.path, contents: nil)
            }
            arPlaneObservationsLogFileHandle = try FileHandle(forWritingTo: arKit.planeObservationsLogURL)
            if !FileManager.default.fileExists(atPath: arKit.lightEstimatesLogURL.path) {
                FileManager.default.createFile(atPath: arKit.lightEstimatesLogURL.path, contents: nil)
            }
            arLightEstimatesLogFileHandle = try FileHandle(forWritingTo: arKit.lightEstimatesLogURL)
            arIntrinsicsWritten = false
        } catch {
            print("Failed to open ARKit frame log: \(error)")
            arFrameLogFileHandle = nil
            arPoseLogFileHandle = nil
            arFeaturePointsLogFileHandle = nil
            arPlaneObservationsLogFileHandle = nil
            arLightEstimatesLogFileHandle = nil
            arIntrinsicsWritten = false
            currentARKitArtifacts = nil
        }
    }

    private func startARSessionIfAvailable() {
        if usingCustomARSessionRecorder {
            print("ℹ️ [AR] startSession skipped — shared ARSession in use")
            return
        }
        guard supportsARCapture, currentARKitArtifacts != nil else {
            if currentARKitArtifacts != nil {
                print("ℹ️ [AR] Capture artifacts prepared but AR session disabled")
            }
            return
        }
        guard !isARRunning else { print("ℹ️ [AR] startSession ignored — already running"); return }
        // If the camera is already owned by our AVCaptureSession/movie output,
        // skip starting AR to avoid camera ownership conflicts that stop recording.
        if session.isRunning || movieOutput.isRecording {
            print("⚠️ [AR] Skipping AR start — camera session is active")
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.environmentTexturing = .automatic
        if supportsMeshReconstruction && ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }

        print("🔵 [AR] run(configuration)")
        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isARRunning = true
    }

    /// Starts the ARSession specifically for ARSessionVideoRecorder usage.
    /// This is called when using the shared ARSession recorder path on iOS 17+.
    private func startARSessionForRecording() {
        guard supportsARCapture else {
            print("⚠️ [AR] Device does not support AR capture")
            return
        }
        guard !isARRunning else {
            print("ℹ️ [AR] startARSessionForRecording ignored — already running")
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.environmentTexturing = .automatic
        if supportsMeshReconstruction && ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }

        print("🔵 [AR] run(configuration) for ARSessionRecorder")
        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isARRunning = true
    }

    private func stopARSession() {
        guard isARRunning else { return }
        print("⚪️ [AR] pause()")
        arSession.pause()
        arDataQueue.sync {
            if let handle = arFrameLogFileHandle {
                do {
                    try handle.close()
                } catch {
                    print("Failed to close ARKit frame log: \(error)")
                }
            }
            arFrameLogFileHandle = nil
            if let handle = arPoseLogFileHandle {
                do {
                    try handle.close()
                } catch {
                    print("Failed to close ARKit pose log: \(error)")
                }
            }
            arPoseLogFileHandle = nil
            for (handle, label) in [
                (arFeaturePointsLogFileHandle, "ARKit feature points log"),
                (arPlaneObservationsLogFileHandle, "ARKit plane observations log"),
                (arLightEstimatesLogFileHandle, "ARKit light estimates log"),
            ] {
                if let handle {
                    do {
                        try handle.close()
                    } catch {
                        print("Failed to close \(label): \(error)")
                    }
                }
            }
            arFeaturePointsLogFileHandle = nil
            arPlaneObservationsLogFileHandle = nil
            arLightEstimatesLogFileHandle = nil
            arIntrinsicsWritten = false
            arFirstFrameTimestamp = nil
        }
        isARRunning = false
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.writeMotionSample(motion)
        }
    }

    private func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
        motionQueue.cancelAllOperations()
        motionLogQueue.sync {
            if let handle = motionLogFileHandle {
                do {
                    try handle.close()
                } catch {
                    // Ignore close errors but surface to the console for debugging
                    print("Failed to close motion log: \(error)")
                }
            }
            motionLogFileHandle = nil
        }
    }

    private func writeMotionSample(_ motion: CMDeviceMotion) {
        guard let artifacts = currentArtifacts else { return }
        let sample = CaptureManifest.MotionSample(
            timestamp: motion.timestamp,
            tCaptureSec: max(0.0, Date().timeIntervalSince(artifacts.startedAt)),
            tMonotonicNs: Self.monotonicNanoseconds(from: motion.timestamp),
            wallTime: Date(),
            motionProvenance: "iphone_device_imu",
            attitude: .init(
                roll: motion.attitude.roll,
                pitch: motion.attitude.pitch,
                yaw: motion.attitude.yaw,
                quaternion: .init(
                    x: motion.attitude.quaternion.x,
                    y: motion.attitude.quaternion.y,
                    z: motion.attitude.quaternion.z,
                    w: motion.attitude.quaternion.w
                )
            ),
            rotationRate: .init(x: motion.rotationRate.x, y: motion.rotationRate.y, z: motion.rotationRate.z),
            gravity: .init(x: motion.gravity.x, y: motion.gravity.y, z: motion.gravity.z),
            userAcceleration: .init(x: motion.userAcceleration.x, y: motion.userAcceleration.y, z: motion.userAcceleration.z)
        )

        motionLogQueue.async { [weak self] in
            guard let self, let handle = self.motionLogFileHandle else { return }
            do {
                let data = try self.motionJSONEncoder.encode(sample)
                handle.write(data)
                if let newline = "\n".data(using: .utf8) {
                    handle.write(newline)
                }
            } catch {
                print("Failed to encode motion sample: \(error)")
            }
        }
    }

    private func writeARFrame(_ frame: ARFrameData) {
        guard let artifacts = currentArtifacts, let arKit = artifacts.arKit else { return }
        guard let handle = arFrameLogFileHandle else { return }

        let frameIndex = arFrameCount
        let frameId = String(format: "%06d", frameIndex + 1)
        let cameraTransform = matrixToArray(frame.transform)
        let intrinsics = matrixToArray(frame.intrinsics)
        let resolution = [Int(frame.imageResolution.width), Int(frame.imageResolution.height)]
        if arFirstFrameTimestamp == nil {
            arFirstFrameTimestamp = frame.timestamp
        }
        let tDeviceSec = Self.deviceTimeSeconds(frameTimestamp: frame.timestamp, firstFrameTimestamp: arFirstFrameTimestamp)
        let tMonotonicNs = Self.monotonicNanoseconds(from: frame.timestamp)

        // --- Entry anchor hold detection (first 60 s, one-shot) ---
        // Operator stands still < 5 cm from starting position for ≥ 2 s.
        var anchorObservations: [String]
        if detectedEntryAnchorHold == nil && tDeviceSec <= 60.0 {
            let currentPos = simd_float3(
                frame.transform.columns.3.x,
                frame.transform.columns.3.y,
                frame.transform.columns.3.z
            )
            if holdCandidateOrigin == nil {
                holdCandidateOrigin = currentPos
                holdCandidateStartTDeviceSec = tDeviceSec
                holdCandidateStartFrameId = frameId
            }
            let distFromOrigin = simd_length(currentPos - holdCandidateOrigin!)
            if distFromOrigin < 0.05 {
                let holdDuration = tDeviceSec - holdCandidateStartTDeviceSec
                if holdDuration >= 2.0 {
                    let midT = holdCandidateStartTDeviceSec + holdDuration / 2.0
                    detectedEntryAnchorHold = EntryAnchorHold(
                        anchorId: "anchor_entry",
                        holdStartFrameId: holdCandidateStartFrameId,
                        holdEndFrameId: frameId,
                        tCaptureSec: midT,
                        durationSec: holdDuration
                    )
                }
                anchorObservations = holdCandidateStartTDeviceSec < tDeviceSec &&
                    (tDeviceSec - holdCandidateStartTDeviceSec) >= 2.0 ? ["anchor_entry"] : []
            } else {
                holdCandidateOrigin = currentPos
                holdCandidateStartTDeviceSec = tDeviceSec
                holdCandidateStartFrameId = frameId
                anchorObservations = []
            }
        } else if let hold = detectedEntryAnchorHold {
            // Continue tagging frames while camera remains near the hold origin
            let currentPos = simd_float3(
                frame.transform.columns.3.x,
                frame.transform.columns.3.y,
                frame.transform.columns.3.z
            )
            let holdOriginPos = holdCandidateOrigin ?? currentPos
            anchorObservations = simd_length(currentPos - holdOriginPos) < 0.05 ? ["anchor_entry"] : []
            _ = hold  // suppress unused warning
        } else {
            anchorObservations = []
        }

        for (anchorId, expiry) in pendingAnchorObservationExpirations where expiry >= tDeviceSec {
            anchorObservations.append(anchorId)
        }
        pendingAnchorObservationExpirations = pendingAnchorObservationExpirations.filter { $0.value >= tDeviceSec }
        anchorObservations = Array(Set(anchorObservations)).sorted()

        var sceneDepthFile: String?
        var smoothedDepthFile: String?
        var confidenceFile: String?
        let depthSource: String?
        let depthValidFraction: Double?
        let missingDepthFraction: Double?

        // Persist a single depth representation per frame to keep raw bundle size bounded.
        // Prefer smoothed depth when available; otherwise fall back to the raw scene depth map.
        if let depthSnapshot = frame.depthSnapshot,
           let depthDirectory = arKit.depthDirectoryURL {
            let filename = "\(frameId).png"
            let fileURL = depthDirectory.appendingPathComponent(filename)
            do {
                try writeDepthPNG(depthSnapshot, to: fileURL)
                let relative = relativePath(for: fileURL, relativeTo: artifacts.directoryURL)
                if depthSnapshot.isSmoothed {
                    smoothedDepthFile = relative
                } else {
                    sceneDepthFile = relative
                }
            } catch {
                print("Failed to persist depth map: \(error)")
            }
        }
        if let confidenceSnapshot = frame.confidenceSnapshot,
           let confidenceDirectory = arKit.confidenceDirectoryURL {
            let filename = "\(frameId).png"
            let fileURL = confidenceDirectory.appendingPathComponent(filename)
            do {
                try writeConfidencePNG(confidenceSnapshot, to: fileURL)
                confidenceFile = relativePath(for: fileURL, relativeTo: artifacts.directoryURL)
            } catch {
                print("Failed to persist confidence map: \(error)")
            }
        }
        if let depthSnapshot = frame.depthSnapshot {
            let totalPixels = max(1, depthSnapshot.width * depthSnapshot.height)
            depthValidFraction = Double(depthSnapshot.validPixelCount) / Double(totalPixels)
            missingDepthFraction = Double(depthSnapshot.missingPixelCount) / Double(totalPixels)
            depthSource = depthSnapshot.isSmoothed ? "smoothed_scene_depth" : "scene_depth"
        } else {
            depthValidFraction = nil
            missingDepthFraction = nil
            depthSource = nil
        }

        // Tracking health fields from ARCamera.
        let (trackingStateStr, trackingReasonStr): (String, String?) = {
            switch frame.trackingState {
            case .normal:
                return ("normal", nil)
            case .limited(let reason):
                let reasonStr: String
                switch reason {
                case .initializing: reasonStr = "initializing"
                case .excessiveMotion: reasonStr = "excessive_motion"
                case .insufficientFeatures: reasonStr = "insufficient_features"
                case .relocalizing: reasonStr = "relocalizing"
                @unknown default: reasonStr = "unknown"
                }
                return ("limited", reasonStr)
            case .notAvailable:
                return ("not_available", nil)
            @unknown default:
                return ("unknown", nil)
            }
        }()

        let worldMappingStr: String? = {
            switch frame.worldMappingStatus {
            case .notAvailable: return "not_available"
            case .limited: return "limited"
            case .extending: return "extending"
            case .mapped: return "mapped"
            @unknown default: return nil
            }
        }()

        // Detect relocalization events: camera is in "limited/relocalizing" state.
        let isRelocalization = trackingStateStr == "limited" && trackingReasonStr == "relocalizing"

        // Exposure metadata from the capture device (the raw pixel buffers are not retained here).
        let exposureDurationS: Double? = videoDevice.map { d in
            let s = d.exposureDuration.seconds
            return s > 0 ? s : nil
        } ?? nil
        let isoValue: Double? = videoDevice.map { d in
            let v = d.iso
            return v > 0 ? Double(v) : nil
        } ?? nil
        let exposureTargetBias: Float? = videoDevice?.exposureTargetBias
        let whiteBalanceGains: CaptureManifest.WhiteBalanceGains? = videoDevice.map { device in
            CaptureManifest.WhiteBalanceGains(
                red: device.deviceWhiteBalanceGains.redGain,
                green: device.deviceWhiteBalanceGains.greenGain,
                blue: device.deviceWhiteBalanceGains.blueGain
            )
        }
        latestARFrameId = frameId
        latestARFrameTCaptureSec = tDeviceSec

        let entry = ARFrameLogEntry(
            frameId: frameId,
            frameIndex: frameIndex,
            timestamp: frame.timestamp,
            tCaptureSec: tDeviceSec,
            tMonotonicNs: tMonotonicNs,
            capturedAt: Date(),
            cameraTransform: cameraTransform,
            intrinsics: intrinsics,
            imageResolution: resolution,
            depthSource: depthSource,
            sceneDepthFile: sceneDepthFile,
            smoothedSceneDepthFile: smoothedDepthFile,
            confidenceFile: confidenceFile,
            depthValidFraction: depthValidFraction,
            missingDepthFraction: missingDepthFraction,
            trackingState: trackingStateStr,
            trackingReason: trackingReasonStr,
            worldMappingStatus: worldMappingStr,
            relocalizationEvent: isRelocalization,
            exposureDurationS: exposureDurationS,
            iso: isoValue,
            exposureTargetBias: exposureTargetBias,
            whiteBalanceGains: whiteBalanceGains,
            sharpnessScore: frame.sharpnessScore,
            anchorObservations: anchorObservations,
            coordinateFrameSessionId: currentRecordingSessionId
        )

        do {
            let data = try arFrameEncoder.encode(entry)
            handle.write(data)
            if let newline = "\n".data(using: .utf8) {
                handle.write(newline)
            }
        } catch {
            print("Failed to encode ARKit frame log entry: \(error)")
        }

        if let featurePointsHandle = arFeaturePointsLogFileHandle {
            let featurePointsEntry = ARFeaturePointLogEntry(
                frameId: frameId,
                tCaptureSec: tDeviceSec,
                tMonotonicNs: tMonotonicNs,
                rawPointCount: frame.rawFeaturePointCount,
                sampledWorldPoints: frame.sampledFeaturePoints.map { [$0.x, $0.y, $0.z] },
                coordinateFrameSessionId: currentRecordingSessionId
            )
            do {
                let data = try arFrameEncoder.encode(featurePointsEntry)
                featurePointsHandle.write(data)
                if let newline = "\n".data(using: .utf8) {
                    featurePointsHandle.write(newline)
                }
            } catch {
                print("Failed to encode ARKit feature points entry: \(error)")
            }
        }

        if let planeObservationsHandle = arPlaneObservationsLogFileHandle {
            for planeAnchor in frame.planeAnchors.prefix(32) {
                let planeEntry = ARPlaneObservationLogEntry(
                    frameId: frameId,
                    tCaptureSec: tDeviceSec,
                    tMonotonicNs: tMonotonicNs,
                    anchorId: planeAnchor.identifier.uuidString,
                    alignment: Self.stringValue(for: planeAnchor.alignment),
                    classification: Self.stringValue(for: planeAnchor.classification),
                    center: [planeAnchor.center.x, planeAnchor.center.y, planeAnchor.center.z],
                    extent: [planeAnchor.extent.x, planeAnchor.extent.y, planeAnchor.extent.z],
                    transform: matrixToArray(planeAnchor.transform),
                    coordinateFrameSessionId: currentRecordingSessionId
                )
                do {
                    let data = try arFrameEncoder.encode(planeEntry)
                    planeObservationsHandle.write(data)
                    if let newline = "\n".data(using: .utf8) {
                        planeObservationsHandle.write(newline)
                    }
                } catch {
                    print("Failed to encode ARKit plane observation entry: \(error)")
                }
            }
        }

        if let lightEstimatesHandle = arLightEstimatesLogFileHandle,
           frame.ambientIntensity != nil || frame.ambientColorTemperature != nil {
            let lightEstimateEntry = ARLightEstimateLogEntry(
                frameId: frameId,
                tCaptureSec: tDeviceSec,
                tMonotonicNs: tMonotonicNs,
                ambientIntensity: frame.ambientIntensity,
                ambientColorTemperature: frame.ambientColorTemperature,
                coordinateFrameSessionId: currentRecordingSessionId
            )
            do {
                let data = try arFrameEncoder.encode(lightEstimateEntry)
                lightEstimatesHandle.write(data)
                if let newline = "\n".data(using: .utf8) {
                    lightEstimatesHandle.write(newline)
                }
            } catch {
                print("Failed to encode ARKit light estimate entry: \(error)")
            }
        }

        // Also append to poses.jsonl with both legacy and bridge-compatible schema.
        // Legacy fields retained: frameIndex, timestamp, transform
        // Bridge fields added: pose_schema_version, frame_id, t_device_sec, T_world_camera
        if let poseHandle = arPoseLogFileHandle {
            let m = frame.transform
            // Convert from SIMD column-major to row-major format for pipeline compatibility
            // Row 0: [m00, m01, m02, tx] = [columns.0.x, columns.1.x, columns.2.x, columns.3.x]
            // Row 1: [m10, m11, m12, ty] = [columns.0.y, columns.1.y, columns.2.y, columns.3.y]
            // Row 2: [m20, m21, m22, tz] = [columns.0.z, columns.1.z, columns.2.z, columns.3.z]
            // Row 3: [m30, m31, m32, 1]  = [columns.0.w, columns.1.w, columns.2.w, columns.3.w]
            let transform: [[Double]] = [
                [Double(m.columns.0.x), Double(m.columns.1.x), Double(m.columns.2.x), Double(m.columns.3.x)],
                [Double(m.columns.0.y), Double(m.columns.1.y), Double(m.columns.2.y), Double(m.columns.3.y)],
                [Double(m.columns.0.z), Double(m.columns.1.z), Double(m.columns.2.z), Double(m.columns.3.z)],
                [Double(m.columns.0.w), Double(m.columns.1.w), Double(m.columns.2.w), Double(m.columns.3.w)]
            ]
            let row = PipelinePoseRow(
                pose_schema_version: Self.poseSchemaVersion,
                frameIndex: frameIndex,
                timestamp: frame.timestamp,
                transform: transform,
                frame_id: frameId,
                t_device_sec: tDeviceSec,
                t_monotonic_ns: tMonotonicNs,
                T_world_camera: transform,
                tracking_state: trackingStateStr,
                tracking_reason: trackingReasonStr,
                world_mapping_status: worldMappingStr,
                coordinate_frame_session_id: currentRecordingSessionId
            )
            do {
                let json = try JSONEncoder().encode(row)
                poseHandle.write(json)
                if let nl = "\n".data(using: .utf8) { poseHandle.write(nl) }
            } catch {
                print("Failed to write poses.jsonl row: \(error)")
            }
        }

        // Write intrinsics.json once per clip
        if !arIntrinsicsWritten {
            let fx = Double(frame.intrinsics.columns.0.x)
            let fy = Double(frame.intrinsics.columns.1.y)
            let cx = Double(frame.intrinsics.columns.2.x)
            let cy = Double(frame.intrinsics.columns.2.y)
            let width = Int(frame.imageResolution.width)
            let height = Int(frame.imageResolution.height)
            let intrinsicsDict: [String: Any] = [
                "fx": fx, "fy": fy, "cx": cx, "cy": cy,
                "width": width, "height": height
            ]
            if let data = try? JSONSerialization.data(withJSONObject: intrinsicsDict, options: [.prettyPrinted]) {
                do { try data.write(to: arKit.intrinsicsURL, options: .atomic); arIntrinsicsWritten = true } catch {
                    print("Failed to write intrinsics.json: \(error)")
                }
            }
        }

        arFrameCount += 1
    }

    private func exportMeshAnchors(_ anchors: [ARAnchor]) {
        guard let meshDirectory = currentArtifacts?.arKit?.meshDirectoryURL else { return }

        for case let meshAnchor as ARMeshAnchor in anchors {
            do {
                try writeMesh(meshAnchor, to: meshDirectory)
                exportedMeshAnchors.insert(meshAnchor.identifier)
            } catch {
                print("Failed to export mesh anchor: \(error)")
            }
        }
    }

    private func startExposureLogging() {
        captureExposureSample()
        exposureTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.captureExposureSample()
        }
    }

    private func stopExposureLogging() {
        exposureTimer?.invalidate()
        exposureTimer = nil
    }

    private func captureExposureSample() {
        guard let device = videoDevice else { return }
        let sample = CaptureManifest.ExposureSample(
            timestamp: Date(),
            iso: device.iso,
            exposureDurationSeconds: device.exposureDuration.seconds,
            exposureTargetBias: device.exposureTargetBias,
            whiteBalanceGains: CaptureManifest.WhiteBalanceGains(
                red: device.deviceWhiteBalanceGains.redGain,
                green: device.deviceWhiteBalanceGains.greenGain,
                blue: device.deviceWhiteBalanceGains.blueGain
            )
        )
        exposureSamples.append(sample)
        persistManifest(duration: nil)
    }

    func markSemanticAnchor(_ anchorType: CaptureSemanticAnchorType, notes: String? = nil) {
        let anchorId = "semantic_\(anchorType.rawValue)"
        let label = anchorType.displayLabel
        var frameId: String?
        var tCaptureSec: Double?
        arDataQueue.sync {
            frameId = latestARFrameId
            tCaptureSec = latestARFrameTCaptureSec
            if let tCaptureSec {
                pendingAnchorObservationExpirations[anchorId] = tCaptureSec + 1.5
            }
        }
        semanticAnchorEvents.append(
            CaptureSemanticAnchorEvent(
                anchorType: anchorType,
                label: label,
                frameId: frameId,
                tCaptureSec: tCaptureSec,
                coordinateFrameSessionId: currentRecordingSessionId,
                notes: notes
            )
        )
    }
}

extension VideoCaptureManager {
    enum CaptureError: LocalizedError {
        case missingCamera
        case archiveUnavailable
        case pixelBufferEncodingFailed

        var errorDescription: String? {
            switch self {
            case .missingCamera:
                return "Unable to access the back camera on this device."
            case .archiveUnavailable:
                return "This device cannot create capture archives."
            case .pixelBufferEncodingFailed:
                return "Unable to persist depth or confidence data."
            }
        }
    }
}

extension VideoCaptureManager: @preconcurrency AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        startARSessionIfAvailable()
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let durationSeconds: Double?
        if output.recordedDuration.isNumeric {
            durationSeconds = CMTimeGetSeconds(output.recordedDuration)
        } else {
            durationSeconds = nil
        }
        handleRecordingCompletion(error: error, durationSeconds: durationSeconds)
    }
}

// Snapshot of all data needed from an ARFrame extracted synchronously on the delegate callback
// thread. Passing only plain values to arDataQueue avoids retaining ARFrame-backed pixel buffers
// across queue hops, which triggers the "retaining N ARFrames" warning and can stall capture.
private struct DepthFrameSnapshot {
    let width: Int
    let height: Int
    let millimeters: [UInt16]
    let isSmoothed: Bool
    let validPixelCount: Int
    let missingPixelCount: Int
}

private struct ConfidenceFrameSnapshot {
    let width: Int
    let height: Int
    let values: [UInt8]
}

private struct ARFrameData {
    let transform: simd_float4x4
    let intrinsics: simd_float3x3
    let imageResolution: CGSize
    let timestamp: TimeInterval
    let trackingState: ARCamera.TrackingState
    let worldMappingStatus: ARFrame.WorldMappingStatus
    let sharpnessScore: Double?
    let depthSnapshot: DepthFrameSnapshot?
    let confidenceSnapshot: ConfidenceFrameSnapshot?
    let rawFeaturePointCount: Int
    let sampledFeaturePoints: [simd_float3]
    let planeAnchors: [ARPlaneAnchor]
    let ambientIntensity: Double?
    let ambientColorTemperature: Double?

    init(
        _ frame: ARFrame,
        sharpnessScore: Double?,
        depthSnapshot: DepthFrameSnapshot?,
        confidenceSnapshot: ConfidenceFrameSnapshot?,
        sampledFeaturePoints: [simd_float3],
        planeAnchors: [ARPlaneAnchor]
    ) {
        transform = frame.camera.transform
        intrinsics = frame.camera.intrinsics
        imageResolution = frame.camera.imageResolution
        timestamp = frame.timestamp
        trackingState = frame.camera.trackingState
        worldMappingStatus = frame.worldMappingStatus
        self.sharpnessScore = sharpnessScore
        self.depthSnapshot = depthSnapshot
        self.confidenceSnapshot = confidenceSnapshot
        rawFeaturePointCount = frame.rawFeaturePoints?.points.count ?? 0
        self.sampledFeaturePoints = sampledFeaturePoints
        self.planeAnchors = planeAnchors
        if let lightEstimate = frame.lightEstimate {
            ambientIntensity = Double(lightEstimate.ambientIntensity)
            ambientColorTemperature = Double(lightEstimate.ambientColorTemperature)
        } else {
            ambientIntensity = nil
            ambientColorTemperature = nil
        }
    }
}

extension VideoCaptureManager: @preconcurrency ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if usingCustomARSessionRecorder {
            if awaitingFirstARVideoFrame {
                awaitingFirstARVideoFrame = false
                currentCameraIntrinsics = makeCameraIntrinsics(from: frame)
                persistManifest(duration: nil)
            }
            appendFrameToARRecorder(
                pixelBuffer: frame.capturedImage,
                timestampSeconds: frame.timestamp,
                resolution: frame.camera.imageResolution
            )
        }
        let shouldPersistDepth = shouldPersistDepthSnapshot(
            at: frame.timestamp,
            cameraTransform: frame.camera.transform
        )
        let depthSnapshot = shouldPersistDepth
            ? Self.makeDepthSnapshot(
                from: frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap,
                isSmoothed: frame.smoothedSceneDepth != nil
            )
            : nil
        let confidenceSnapshot = shouldPersistDepth
            ? Self.makeConfidenceSnapshot(
                from: frame.smoothedSceneDepth?.confidenceMap ?? frame.sceneDepth?.confidenceMap
            )
            : nil
        let sharpnessScore = Self.laplacianVariance(pixelBuffer: frame.capturedImage)
        let sampledFeaturePoints = Self.sampledFeaturePoints(from: frame)
        let planeAnchors = session.currentFrame?.anchors.compactMap { $0 as? ARPlaneAnchor } ?? []
        let snapshot = ARFrameData(
            frame,
            sharpnessScore: sharpnessScore,
            depthSnapshot: depthSnapshot,
            confidenceSnapshot: confidenceSnapshot,
            sampledFeaturePoints: sampledFeaturePoints,
            planeAnchors: planeAnchors
        )
        arDataQueue.async { [weak self] in
            self?.writeARFrame(snapshot)
        }
        qualityMonitor.updateFromARFrame(frame)
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        arDataQueue.async { [weak self] in
            self?.exportMeshAnchors(anchors)
        }
        let meshCount = session.currentFrame?.anchors.compactMap({ $0 as? ARMeshAnchor }).count ?? 0
        qualityMonitor.updateMeshAnchorCount(meshCount)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        arDataQueue.async { [weak self] in
            self?.exportMeshAnchors(anchors)
        }
        let meshCount = session.currentFrame?.anchors.compactMap({ $0 as? ARMeshAnchor }).count ?? 0
        qualityMonitor.updateMeshAnchorCount(meshCount)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("❌ [AR] session failed: \(error.localizedDescription)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentARKitArtifacts = nil
            self.stopARSession()
        }
    }
}

@available(iOS 17.0, *)
private final class ARSessionVideoRecorder {
    private enum RecorderError: LocalizedError {
        case unableToAddInput
        case writerFailed
        case noFramesRecorded

        var errorDescription: String? {
            switch self {
            case .unableToAddInput:
                return "Unable to add video input to the asset writer."
            case .writerFailed:
                return "The video writer failed to start."
            case .noFramesRecorded:
                return "No AR frames were captured during recording."
            }
        }
    }

    private let queue = DispatchQueue(label: "com.blueprint.capture.arvideo")
    private let assetWriter: AVAssetWriter
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private let orientation: UIInterfaceOrientation
    private let errorHandler: (Error) -> Void
    private var startTime: CMTime?
    private var lastTime: CMTime?
    private var recordedFrameCount = 0
    private var isFinishing = false

    init(destinationURL: URL, orientation: UIInterfaceOrientation, errorHandler: @escaping (Error) -> Void) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        assetWriter = try AVAssetWriter(outputURL: destinationURL, fileType: .mov)
        assetWriter.shouldOptimizeForNetworkUse = true
        self.orientation = orientation
        self.errorHandler = errorHandler
    }

    func append(pixelBuffer: CVPixelBuffer, timestampSeconds: TimeInterval, resolution: CGSize) {
        // Capture the pixelBuffer strongly into the async block to keep it alive.
        queue.async { [pixelBuffer] in
            guard !self.isFinishing else { return }
            do {
                if self.assetWriter.status == .failed {
                    throw self.assetWriter.error ?? RecorderError.writerFailed
                }
                try self.prepareIfNeeded(resolution: resolution)
                try self.appendFrame(pixelBuffer: pixelBuffer, timestampSeconds: timestampSeconds)
            } catch {
                self.isFinishing = true
                self.assetWriter.cancelWriting()
                DispatchQueue.main.async {
                    self.errorHandler(error)
                }
            }
        }
    }

    func finishRecording(completion: @escaping (Result<Double?, Error>) -> Void) {
        queue.async {
            guard !self.isFinishing else { return }
            self.isFinishing = true

            if self.assetWriter.status == .failed {
                let error = self.assetWriter.error ?? RecorderError.writerFailed
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard self.recordedFrameCount > 0 else {
                self.assetWriter.cancelWriting()
                DispatchQueue.main.async { completion(.failure(RecorderError.noFramesRecorded)) }
                return
            }

            self.videoInput?.markAsFinished()
            self.assetWriter.finishWriting {
                let writerError = self.assetWriter.error
                let duration: Double?
                if let start = self.startTime, let end = self.lastTime {
                    duration = CMTimeSubtract(end, start).seconds
                } else {
                    duration = nil
                }
                DispatchQueue.main.async {
                    if let writerError {
                        completion(.failure(writerError))
                    } else {
                        completion(.success(duration))
                    }
                }
            }
        }
    }

    private func prepareIfNeeded(resolution: CGSize) throws {
        guard videoInput == nil, adaptor == nil else { return }
        let width = Int(resolution.width)
        let height = Int(resolution.height)
        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 8,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoExpectedSourceFrameRateKey: 30
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = true
        input.transform = transform(for: orientation)
        guard assetWriter.canAdd(input) else { throw RecorderError.unableToAddInput }
        assetWriter.add(input)

        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        videoInput = input
    }

    private func appendFrame(pixelBuffer: CVPixelBuffer, timestampSeconds: TimeInterval) throws {
        guard let input = videoInput, let adaptor = adaptor else { return }

        let timestamp = CMTime(seconds: timestampSeconds, preferredTimescale: 600)
        if startTime == nil {
            startTime = timestamp
            guard assetWriter.startWriting() else { throw assetWriter.error ?? RecorderError.writerFailed }
            assetWriter.startSession(atSourceTime: timestamp)
        }

        guard input.isReadyForMoreMediaData else { return }

        if adaptor.append(pixelBuffer, withPresentationTime: timestamp) {
            lastTime = timestamp
            recordedFrameCount += 1
        } else {
            throw RecorderError.writerFailed
        }
    }

    private func transform(for orientation: UIInterfaceOrientation) -> CGAffineTransform {
        switch orientation {
        case .portrait:
            return CGAffineTransform(rotationAngle: .pi / 2)
        case .portraitUpsideDown:
            return CGAffineTransform(rotationAngle: -.pi / 2)
        case .landscapeLeft:
            return CGAffineTransform(rotationAngle: .pi)
        default:
            return .identity
        }
    }
}

private extension VideoCaptureManager {
    func cleanupAfterRecording() {
        print("🧹 [Capture] cleanupAfterRecording")
        currentArtifacts = nil
        currentARKitArtifacts = nil
        currentCameraIntrinsics = nil
        currentExposureSettings = nil
        exposureSamples = []
        screenRecordingWriter = nil
        screenRecordingStartDate = nil
        screenRecordingStopDate = nil
        screenRecorderStopTimeoutWorkItem?.cancel()
        screenRecorderStopTimeoutWorkItem = nil
        awaitingScreenRecorderCompletion = false
        usingScreenRecorder = false
        lastCaptureUsedScreenRecorder = false
        usingCustomARSessionRecorder = false
        awaitingFirstARVideoFrame = false
        arSessionRecorder = nil
        currentRecordingSessionId = nil
        arDataQueue.async { [weak self] in
            self?.arFrameCount = 0
            self?.arFirstFrameTimestamp = nil
            self?.lastDepthSnapshotTimestamp = nil
            self?.lastDepthSnapshotPosition = nil
            self?.latestARFrameId = nil
            self?.latestARFrameTCaptureSec = nil
            self?.pendingAnchorObservationExpirations = [:]
            self?.exportedMeshAnchors.removeAll()
        }
    }

    func persistManifest(duration: Double?, synchronous: Bool = false) {
        guard let artifacts = currentArtifacts else { return }
        let intr = currentCameraIntrinsics
        let width = intr?.resolutionWidth ?? 0
        let height = intr?.resolutionHeight ?? 0
        // Pipeline expects fps_source as a float
        let fps: Double = {
            if lastCaptureUsedScreenRecorder {
                return Double(UIScreen.main.maximumFramesPerSecond)
            }
            if let d = videoDevice?.activeVideoMinFrameDuration, d.isNumeric { return round(1.0 / d.seconds) }
            return 30.0
        }()
        let deviceModel = UIDevice.current.model
        let hardwareIdentifier = Self.hardwareModelIdentifier()
        let osVersion = UIDevice.current.systemVersion
        let osBuild = Self.operatingSystemBuild()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let appBuild = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "unknown"
        let hasLiDAR = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        let epochMs = Int64(artifacts.startedAt.timeIntervalSince1970 * 1000.0)
        let captureStartTime = artifacts.startedAt
        let recordingSessionId = currentRecordingSessionId ?? latestRecordingSession?.coordinateFrameSessionId

        // Convert exposure samples into raw evidence timing relative to capture start.
        let pipelineExposureSamples: [[String: Any]] = self.exposureSamples.map { sample in
            // Convert timestamp to seconds from capture start
            let timestampSeconds = sample.timestamp.timeIntervalSince(captureStartTime)
            return [
                "iso": Double(sample.iso),
                "exposure_duration": sample.exposureDurationSeconds,
                "timestamp": timestampSeconds
            ]
        }

        let writeBlock = { [self] in
            var dict: [String: Any] = [
                // Required raw capture fields.
                "schema_version": "v3",
                "scene_id": "",  // Will be patched by upload service
                "video_uri": "", // Will be patched by upload service
                "device_model": hardwareIdentifier,
                "device_model_marketing": deviceModel,
                "os_version": osVersion,
                "ios_version": osVersion,
                "ios_build": osBuild,
                "app_version": appVersion,
                "app_build": appBuild,
                "hardware_model_identifier": hardwareIdentifier,
                "fps_source": fps,
                "width": width,
                "height": height,
                "capture_start_epoch_ms": epochMs,
                "has_lidar": hasLiDAR,
                "depth_supported": hasLiDAR,
                "capture_schema_version": Self.captureSchemaVersion,
                "capture_source": Self.captureSource,
                "capture_tier_hint": Self.captureTierHint,
                "recording_session_id": recordingSessionId as Any,
                "coordinate_frame_session_id": recordingSessionId as Any,
                // Optional fields that help downstream scene-memory derivation.
                "scale_hint_m_per_unit": 1.0,
                "intended_space_type": "industrial_unknown"
            ]

            // Exposure samples stay in the raw bundle for downstream use.
            if !pipelineExposureSamples.isEmpty {
                dict["exposure_samples"] = pipelineExposureSamples
            }
            if let intr {
                var cameraIntrinsics: [String: Any] = [
                    "resolution_width": intr.resolutionWidth,
                    "resolution_height": intr.resolutionHeight,
                ]
                if let intrinsicMatrix = intr.intrinsicMatrix {
                    cameraIntrinsics["intrinsic_matrix"] = intrinsicMatrix
                }
                if let fieldOfView = intr.fieldOfView {
                    cameraIntrinsics["field_of_view"] = fieldOfView
                }
                if let lensAperture = intr.lensAperture {
                    cameraIntrinsics["lens_aperture"] = lensAperture
                }
                if let minimumFocusDistance = intr.minimumFocusDistance {
                    cameraIntrinsics["minimum_focus_distance"] = minimumFocusDistance
                }
                dict["camera_intrinsics"] = cameraIntrinsics
            }
            if let currentExposureSettings = self.currentExposureSettings {
                var exposureSettings: [String: Any] = [
                    "mode": currentExposureSettings.mode,
                    "white_balance_mode": currentExposureSettings.whiteBalanceMode,
                ]
                if let pointOfInterest = currentExposureSettings.pointOfInterest {
                    exposureSettings["point_of_interest"] = pointOfInterest
                }
                dict["exposure_settings"] = exposureSettings
            }
            dict["device_camera"] = [
                "position": "back",
                "uses_ar_session_recorder": self.canUseARSessionRecorder,
                "has_scene_depth_semantics": hasLiDAR,
            ]
            do {
                let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .withoutEscapingSlashes])
                try data.write(to: artifacts.manifestURL, options: .atomic)
            } catch {
                print("Failed to write manifest: \(error)")
            }
        }

        if synchronous {
            manifestQueue.sync(execute: writeBlock)
        } else {
            manifestQueue.async(execute: writeBlock)
        }
    }

    func makeCameraIntrinsics(from device: AVCaptureDevice) -> CaptureManifest.CameraIntrinsics {
        let description = device.activeFormat.formatDescription
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        var intrinsicMatrix: [Double]?
        let intrinsicKey: CFString = "CameraIntrinsicMatrix" as CFString
        if let cfData = CMFormatDescriptionGetExtension(description, extensionKey: intrinsicKey) as? Data {
            intrinsicMatrix = cfData.withUnsafeBytes { rawBuffer -> [Double]? in
                let floatCount = rawBuffer.count / MemoryLayout<Float32>.size
                guard floatCount == 9 else { return nil }
                let floatBuffer = rawBuffer.bindMemory(to: Float32.self)
                return floatBuffer.map { Double($0) }
            }
        }

        return CaptureManifest.CameraIntrinsics(
            resolutionWidth: Int(dimensions.width),
            resolutionHeight: Int(dimensions.height),
            intrinsicMatrix: intrinsicMatrix,
            fieldOfView: device.activeFormat.videoFieldOfView,
            lensAperture: device.lensAperture,
            minimumFocusDistance: device.minimumFocusDistance > 0 ? Float(device.minimumFocusDistance) : nil
        )
    }

    func makeCameraIntrinsics(from frame: ARFrame) -> CaptureManifest.CameraIntrinsics {
        let intrinsics = frame.camera.intrinsics
        let matrix: [Double] = [
            Double(intrinsics.columns.0.x), Double(intrinsics.columns.0.y), Double(intrinsics.columns.0.z),
            Double(intrinsics.columns.1.x), Double(intrinsics.columns.1.y), Double(intrinsics.columns.1.z),
            Double(intrinsics.columns.2.x), Double(intrinsics.columns.2.y), Double(intrinsics.columns.2.z)
        ]

        let resolution = frame.camera.imageResolution
        return CaptureManifest.CameraIntrinsics(
            resolutionWidth: Int(resolution.width),
            resolutionHeight: Int(resolution.height),
            intrinsicMatrix: matrix,
            fieldOfView: nil,
            lensAperture: nil,
            minimumFocusDistance: nil
        )
    }

    func makeScreenIntrinsics() -> CaptureManifest.CameraIntrinsics {
        let bounds = UIScreen.main.nativeBounds
        return CaptureManifest.CameraIntrinsics(
            resolutionWidth: Int(bounds.width),
            resolutionHeight: Int(bounds.height),
            intrinsicMatrix: nil,
            fieldOfView: nil,
            lensAperture: nil,
            minimumFocusDistance: nil
        )
    }

    func makeExposureSettings(from device: AVCaptureDevice) -> CaptureManifest.ExposureSettings {
        let mode: String
        switch device.exposureMode {
        case .autoExpose: mode = "autoExpose"
        case .continuousAutoExposure: mode = "continuousAutoExposure"
        case .custom: mode = "custom"
        case .locked: mode = "locked"
        @unknown default: mode = "unknown"
        }

        let whiteBalanceMode: String
        switch device.whiteBalanceMode {
        case .autoWhiteBalance: whiteBalanceMode = "autoWhiteBalance"
        case .continuousAutoWhiteBalance: whiteBalanceMode = "continuousAutoWhiteBalance"
        case .locked: whiteBalanceMode = "locked"
        @unknown default: whiteBalanceMode = "unknown"
        }

        let pointOfInterest: [Double]?
        if device.isExposurePointOfInterestSupported {
            pointOfInterest = [Double(device.exposurePointOfInterest.x), Double(device.exposurePointOfInterest.y)]
        } else {
            pointOfInterest = nil
        }

        return CaptureManifest.ExposureSettings(
            mode: mode,
            pointOfInterest: pointOfInterest,
            whiteBalanceMode: whiteBalanceMode
        )
    }

    func makeARSessionExposureSettings() -> CaptureManifest.ExposureSettings {
        CaptureManifest.ExposureSettings(
            mode: "arSession",
            pointOfInterest: nil,
            whiteBalanceMode: "automatic"
        )
    }

    func makeARKitManifest(for artifacts: RecordingArtifacts) -> CaptureManifest.ARKitArtifacts? {
        guard let arKit = artifacts.arKit else { return nil }
        let frameCount = arDataQueue.sync { arFrameCount }

        return CaptureManifest.ARKitArtifacts(
            frameLogFile: relativePath(for: arKit.frameLogURL, relativeTo: artifacts.directoryURL),
            depthDirectory: arKit.depthDirectoryURL.map { relativePath(for: $0, relativeTo: artifacts.directoryURL) },
            confidenceDirectory: arKit.confidenceDirectoryURL.map { relativePath(for: $0, relativeTo: artifacts.directoryURL) },
            meshDirectory: arKit.meshDirectoryURL.map { relativePath(for: $0, relativeTo: artifacts.directoryURL) },
            frameCount: frameCount
        )
    }

    func relativePath(for url: URL, relativeTo directory: URL) -> String {
        let path = url.standardizedFileURL.path
        let basePath = directory.standardizedFileURL.path
        guard path.hasPrefix(basePath) else {
            return url.lastPathComponent
        }

        let startIndex = path.index(path.startIndex, offsetBy: basePath.count)
        var relative = String(path[startIndex...])
        while relative.hasPrefix("/") {
            relative.removeFirst()
        }

        return relative.isEmpty ? url.lastPathComponent : relative
    }

    func shouldPersistDepthSnapshot(at timestamp: TimeInterval, cameraTransform: simd_float4x4) -> Bool {
        let currentPosition = simd_float3(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )
        guard let lastSnapshotTimestamp = lastDepthSnapshotTimestamp else {
            lastDepthSnapshotTimestamp = timestamp
            lastDepthSnapshotPosition = currentPosition
            return true
        }
        let elapsed = timestamp - lastSnapshotTimestamp
        let travelMeters: Float = {
            guard let lastPosition = lastDepthSnapshotPosition else { return .greatestFiniteMagnitude }
            return simd_length(currentPosition - lastPosition)
        }()
        let threshold = travelMeters >= Self.minimumDepthTravelMeters
            ? Self.movingDepthSnapshotIntervalSeconds
            : Self.stationaryDepthSnapshotIntervalSeconds
        guard elapsed >= threshold else {
            return false
        }
        lastDepthSnapshotTimestamp = timestamp
        lastDepthSnapshotPosition = currentPosition
        return true
    }

    static func makeDepthSnapshot(from pixelBuffer: CVPixelBuffer?, isSmoothed: Bool) -> DepthFrameSnapshot? {
        guard let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let rowFloats = bytesPerRow / MemoryLayout<Float32>.size
        let src = base.assumingMemoryBound(to: Float32.self)
        var millimeters = [UInt16](repeating: 0, count: width * height)
        var validPixelCount = 0
        var missingPixelCount = 0
        millimeters.withUnsafeMutableBufferPointer { buffer in
            guard let destination = buffer.baseAddress else { return }
            for y in 0..<height {
                let srcRow = src.advanced(by: y * rowFloats)
                let dstRow = destination.advanced(by: y * width)
                for x in 0..<width {
                    let meters = srcRow[x]
                    let mm = meters.isFinite && meters > 0 ? min(max(Int(meters * 1000.0), 0), 65535) : 0
                    dstRow[x] = UInt16(mm)
                    if mm > 0 {
                        validPixelCount += 1
                    } else {
                        missingPixelCount += 1
                    }
                }
            }
        }

        return DepthFrameSnapshot(
            width: width,
            height: height,
            millimeters: millimeters,
            isSmoothed: isSmoothed,
            validPixelCount: validPixelCount,
            missingPixelCount: missingPixelCount
        )
    }

    static func makeConfidenceSnapshot(from pixelBuffer: CVPixelBuffer?) -> ConfidenceFrameSnapshot? {
        guard let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        var values = [UInt8](repeating: 0, count: width * height)
        values.withUnsafeMutableBufferPointer { buffer in
            guard let destination = buffer.baseAddress else { return }
            for y in 0..<height {
                let srcRow = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                let dstRow = destination.advanced(by: y * width)
                dstRow.assign(from: srcRow, count: width)
            }
        }

        return ConfidenceFrameSnapshot(width: width, height: height, values: values)
    }

    func writeFloatPixelBuffer(_ pixelBuffer: CVPixelBuffer, to url: URL) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw CaptureError.pixelBufferEncodingFailed
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let floatsPerRow = bytesPerRow / MemoryLayout<Float32>.size

        var values = [Float32](repeating: 0, count: width * height)
        values.withUnsafeMutableBufferPointer { buffer in
            let floatPointer = baseAddress.assumingMemoryBound(to: Float32.self)
            for y in 0..<height {
                let destination = buffer.baseAddress!.advanced(by: y * width)
                let source = floatPointer.advanced(by: y * floatsPerRow)
                destination.assign(from: source, count: width)
            }
        }

        let data = values.withUnsafeBytes { Data($0) }
        try data.write(to: url, options: .atomic)
    }

    func writeUInt8PixelBuffer(_ pixelBuffer: CVPixelBuffer, to url: URL) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw CaptureError.pixelBufferEncodingFailed
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        var values = [UInt8](repeating: 0, count: width * height)
        values.withUnsafeMutableBufferPointer { buffer in
            for y in 0..<height {
                let destination = buffer.baseAddress!.advanced(by: y * width)
                let source = baseAddress.advanced(by: y * bytesPerRow)
                destination.assign(from: source.assumingMemoryBound(to: UInt8.self), count: width)
            }
        }

        let data = Data(values)
        try data.write(to: url, options: .atomic)
    }

    func writeDepthPNG(_ pixelBuffer: CVPixelBuffer, to url: URL) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { throw CaptureError.pixelBufferEncodingFailed }

        // Convert Float32 meters to UInt16 millimeters (clamped)
        var out = [UInt16](repeating: 0, count: width * height)
        let rowFloats = bytesPerRow / MemoryLayout<Float32>.size
        let src = base.assumingMemoryBound(to: Float32.self)
        for y in 0..<height {
            let srcRow = src.advanced(by: y * rowFloats)
            let dstRow = UnsafeMutablePointer(mutating: out).advanced(by: y * width)
            for x in 0..<width {
                let m = srcRow[x]
                let mm = m.isFinite && m > 0 ? min(max(Int(m * 1000.0), 0), 65535) : 0
                dstRow[x] = UInt16(mm)
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &out,
            width: width,
            height: height,
            bitsPerComponent: 16,
            bytesPerRow: width * MemoryLayout<UInt16>.size,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let image = ctx.makeImage() else {
            throw CaptureError.pixelBufferEncodingFailed
        }
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        if !CGImageDestinationFinalize(dest) { throw CaptureError.pixelBufferEncodingFailed }
    }

    func writeDepthPNG(_ snapshot: DepthFrameSnapshot, to url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = snapshot.millimeters
        guard let ctx = CGContext(
            data: &pixels,
            width: snapshot.width,
            height: snapshot.height,
            bitsPerComponent: 16,
            bytesPerRow: snapshot.width * MemoryLayout<UInt16>.size,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let image = ctx.makeImage() else {
            throw CaptureError.pixelBufferEncodingFailed
        }
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        if !CGImageDestinationFinalize(dest) { throw CaptureError.pixelBufferEncodingFailed }
    }

    func writeConfidencePNG(_ pixelBuffer: CVPixelBuffer, to url: URL) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { throw CaptureError.pixelBufferEncodingFailed }

        var out = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let srcRow = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            let dstRow = UnsafeMutablePointer(mutating: out).advanced(by: y * width)
            for x in 0..<width {
                dstRow[x] = srcRow[x] // values {0,1,2}
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &out,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * MemoryLayout<UInt8>.size,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let image = ctx.makeImage() else {
            throw CaptureError.pixelBufferEncodingFailed
        }
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        if !CGImageDestinationFinalize(dest) { throw CaptureError.pixelBufferEncodingFailed }
    }

    func writeConfidencePNG(_ snapshot: ConfidenceFrameSnapshot, to url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = snapshot.values
        guard let ctx = CGContext(
            data: &pixels,
            width: snapshot.width,
            height: snapshot.height,
            bitsPerComponent: 8,
            bytesPerRow: snapshot.width * MemoryLayout<UInt8>.size,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let image = ctx.makeImage() else {
            throw CaptureError.pixelBufferEncodingFailed
        }
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        if !CGImageDestinationFinalize(dest) { throw CaptureError.pixelBufferEncodingFailed }
    }

    func packageArtifacts(_ artifacts: RecordingArtifacts) throws {
        #if canImport(ZIPFoundation)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: artifacts.packageURL.path) {
            try fileManager.removeItem(at: artifacts.packageURL)
        }
        try fileManager.zipItem(
            at: artifacts.directoryURL,
            to: artifacts.packageURL,
            shouldKeepParent: true
        )
        #else
        // No-op: we will upload the directory contents recursively
        return
        #endif
    }

    func matrixToArray(_ matrix: simd_float4x4) -> [Float] {
        var values: [Float] = []
        values.reserveCapacity(16)
        for column in 0..<4 {
            let col = matrix[column]
            values.append(col.x)
            values.append(col.y)
            values.append(col.z)
            values.append(col.w)
        }
        return values
    }

    func matrixToArray(_ matrix: simd_float3x3) -> [Float] {
        var values: [Float] = []
        values.reserveCapacity(9)
        for column in 0..<3 {
            let col = matrix[column]
            values.append(col.x)
            values.append(col.y)
            values.append(col.z)
        }
        return values
    }

    func writeMesh(_ anchor: ARMeshAnchor, to directory: URL) throws {
        let geometry = anchor.geometry
        let vertexCount = geometry.vertices.count
        var lines: [String] = ["# ARKit mesh anchor \(anchor.identifier.uuidString)"]

        for index in 0..<vertexCount {
            let vertex = geometry.vertex(at: index)
            let worldPosition = anchor.transform * simd_float4(vertex, 1.0)
            lines.append(String(format: "v %.6f %.6f %.6f", worldPosition.x, worldPosition.y, worldPosition.z))
        }

        if geometry.hasNormals {
            let c0 = simd_float3(anchor.transform.columns.0.x, anchor.transform.columns.0.y, anchor.transform.columns.0.z)
            let c1 = simd_float3(anchor.transform.columns.1.x, anchor.transform.columns.1.y, anchor.transform.columns.1.z)
            let c2 = simd_float3(anchor.transform.columns.2.x, anchor.transform.columns.2.y, anchor.transform.columns.2.z)
            let rotation = simd_float3x3(columns: (c0, c1, c2))
            for index in 0..<geometry.normals.count {
                let normal = geometry.normal(at: index)
                let worldNormal = normalize(rotation * normal)
                lines.append(String(format: "vn %.6f %.6f %.6f", worldNormal.x, worldNormal.y, worldNormal.z))
            }
        }

        let faceCount = geometry.faceCount
        for faceIndex in 0..<faceCount {
            let indices = geometry.faceIndices(at: faceIndex)
            guard indices.count >= 3 else { continue }
            let a = indices[0] + 1
            let b = indices[1] + 1
            let c = indices[2] + 1
            if geometry.hasNormals {
                lines.append("f \(a)//\(a) \(b)//\(b) \(c)//\(c)")
            } else {
                lines.append("f \(a) \(b) \(c)")
            }
        }

        let fileURL = directory.appendingPathComponent("mesh-\(anchor.identifier.uuidString).obj")
        try lines.joined(separator: "\n").appending("\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

private extension CMTime {
    var seconds: Double {
        guard isNumeric else { return 0 }
        return CMTimeGetSeconds(self)
    }
}

extension VideoCaptureManager.CaptureState {
    var artifacts: VideoCaptureManager.RecordingArtifacts? {
        switch self {
        case .recording(let artifacts), .finished(let artifacts):
            return artifacts
        case .idle, .error:
            return nil
        }
    }

    func currentInterfaceOrientation() -> UIInterfaceOrientation {
        if Thread.isMainThread {
            return resolveInterfaceOrientation()
        } else {
            var orientation: UIInterfaceOrientation = .portrait
            DispatchQueue.main.sync {
                orientation = self.resolveInterfaceOrientation()
            }
            return orientation
        }
    }

    func screenRecordingOutputSize(for orientation: UIInterfaceOrientation) -> CGSize {
        let bounds = UIScreen.main.nativeBounds
        switch orientation {
        case .landscapeLeft, .landscapeRight:
            return CGSize(width: bounds.height, height: bounds.width)
        default:
            return CGSize(width: bounds.width, height: bounds.height)
        }
    }

    private func resolveInterfaceOrientation() -> UIInterfaceOrientation {
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) {
            return windowScene.interfaceOrientation
        }
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            return windowScene.interfaceOrientation
        }
        return .portrait
    }

    var uploadPayload: VideoCaptureManager.CaptureUploadPayload? {
        artifacts?.uploadPayload
    }
}

extension VideoCaptureManager {
    struct CaptureManifest: Codable, Equatable {
        struct CameraIntrinsics: Codable, Equatable {
            let resolutionWidth: Int
            let resolutionHeight: Int
            let intrinsicMatrix: [Double]?
            let fieldOfView: Float?
            let lensAperture: Float?
            let minimumFocusDistance: Float?
        }

        struct ExposureSettings: Codable, Equatable {
            let mode: String
            let pointOfInterest: [Double]?
            let whiteBalanceMode: String
        }

        struct WhiteBalanceGains: Codable, Equatable {
            let red: Float
            let green: Float
            let blue: Float
        }

        struct ExposureSample: Codable, Equatable {
            let timestamp: Date
            let iso: Float
            let exposureDurationSeconds: Double
            let exposureTargetBias: Float
            let whiteBalanceGains: WhiteBalanceGains
        }

        struct Quaternion: Codable, Equatable {
            let x: Double
            let y: Double
            let z: Double
            let w: Double
        }

        struct Vector3: Codable, Equatable {
            let x: Double
            let y: Double
            let z: Double
        }

        struct Attitude: Codable, Equatable {
            let roll: Double
            let pitch: Double
            let yaw: Double
            let quaternion: Quaternion
        }

        struct MotionSample: Codable, Equatable {
            let timestamp: TimeInterval
            let tCaptureSec: Double
            let tMonotonicNs: Int64
            let wallTime: Date
            let motionProvenance: String
            let attitude: Attitude
            let rotationRate: Vector3
            let gravity: Vector3
            let userAcceleration: Vector3
        }

        let videoFile: String
        let motionLogFile: String
        let manifestFile: String
        let recordedAt: Date
        let durationSeconds: Double?
        let cameraIntrinsics: CameraIntrinsics
        let exposureSettings: ExposureSettings
        let exposureSamples: [ExposureSample]
        let arKit: ARKitArtifacts?

        struct ARKitArtifacts: Codable, Equatable {
            let frameLogFile: String
            let depthDirectory: String?
            let confidenceDirectory: String?
            let meshDirectory: String?
            let frameCount: Int
        }
    }
}

private extension VideoCaptureManager {
    static func hardwareModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    static func operatingSystemBuild() -> String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        let result = sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
        guard result == 0 else { return "unknown" }
        return String(cString: buffer)
    }

    static func stringValue(for alignment: ARPlaneAnchor.Alignment) -> String {
        switch alignment {
        case .horizontal:
            return "horizontal"
        case .vertical:
            return "vertical"
        @unknown default:
            return "unknown"
        }
    }

    static func stringValue(for classification: ARPlaneAnchor.Classification) -> String? {
        switch classification {
        case .none:
            return nil
        case .wall:
            return "wall"
        case .floor:
            return "floor"
        case .ceiling:
            return "ceiling"
        case .table:
            return "table"
        case .seat:
            return "seat"
        case .window:
            return "window"
        case .door:
            return "door"
        @unknown default:
            return "unknown"
        }
    }
}

private extension ARMeshGeometry {
    var hasNormals: Bool { normals.count > 0 }

    var faceCount: Int {
        let perPrimitive = indicesPerPrimitive
        guard perPrimitive > 0 else { return 0 }
        let totalBytes = faces.buffer.length
        let totalIndices = totalBytes / faces.bytesPerIndex
        return totalIndices / perPrimitive
    }

    var indicesPerPrimitive: Int {
        switch faces.primitiveType {
        case .triangle:
            return 3
        case .line:
            return 2
        @unknown default:
            return 3
        }
    }

    func vertex(at index: Int) -> simd_float3 {
        vector(from: vertices, at: index)
    }

    func normal(at index: Int) -> simd_float3 {
        vector(from: normals, at: index)
    }

    func faceIndices(at index: Int) -> [UInt32] {
        let perPrimitive = indicesPerPrimitive
        let primitiveStart = index * perPrimitive
        let totalBytes = faces.buffer.length
        let totalIndices = totalBytes / faces.bytesPerIndex
        guard perPrimitive > 0, primitiveStart + perPrimitive <= totalIndices else { return [] }

        let byteOffset = primitiveStart * faces.bytesPerIndex
        let pointer = faces.buffer.contents().advanced(by: byteOffset)

        let bpi = faces.bytesPerIndex
        if bpi == MemoryLayout<UInt16>.size {
            let base = pointer.assumingMemoryBound(to: UInt16.self)
            return (0..<perPrimitive).map { UInt32(base[$0]) }
        } else if bpi == MemoryLayout<UInt32>.size {
            let base = pointer.assumingMemoryBound(to: UInt32.self)
            return (0..<perPrimitive).map { base[$0] }
        } else {
            return []
        }
    }

    private func vector(from source: ARGeometrySource, at index: Int) -> simd_float3 {
        let stride = source.stride
        let offset = source.offset
        let pointer = source.buffer.contents().advanced(by: offset + index * stride)
        let floatPointer = pointer.assumingMemoryBound(to: Float.self)
        return simd_float3(floatPointer[0], floatPointer[1], floatPointer[2])
    }
}
// yeye
