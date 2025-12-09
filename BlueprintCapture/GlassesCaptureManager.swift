import Foundation
import Combine
import AVFoundation
import UIKit
import CoreMotion

// Import Meta DAT SDK modules when available
// The SDK provides: MWDATCore, MWDATCamera, MWDATMockDevice
#if canImport(MWDATCore)
import MWDATCore
#endif
#if canImport(MWDATCamera)
import MWDATCamera
#endif
#if canImport(MWDATMockDevice)
import MWDATMockDevice
#endif

/// Manages video capture from Meta smart glasses via the MWDAT SDK.
/// Supports both real device connections and MockDeviceKit for testing.
@MainActor
final class GlassesCaptureManager: NSObject, ObservableObject {

    // MARK: - Types

    enum ConnectionState: Equatable {
        case disconnected
        case scanning
        case connecting
        case connected(deviceName: String)
        case error(String)
    }

    enum CaptureState: Equatable {
        case idle
        case preparing
        case streaming(StreamingInfo)
        case paused
        case finished(CaptureArtifacts)
        case error(String)

        var isActive: Bool {
            switch self {
            case .streaming, .paused:
                return true
            default:
                return false
            }
        }
    }

    struct StreamingInfo: Equatable {
        let startedAt: Date
        let frameCount: Int
        let resolution: CGSize
        let fps: Double
        let durationSeconds: Double

        static func == (lhs: StreamingInfo, rhs: StreamingInfo) -> Bool {
            lhs.startedAt == rhs.startedAt &&
            lhs.frameCount == rhs.frameCount &&
            lhs.durationSeconds == rhs.durationSeconds
        }
    }

    struct CaptureArtifacts: Equatable {
        let baseFilename: String
        let directoryURL: URL
        let videoURL: URL
        let framesDirectoryURL: URL
        let motionLogURL: URL
        let manifestURL: URL
        let packageURL: URL
        let startedAt: Date
        let endedAt: Date
        let frameCount: Int
        let durationSeconds: Double

        var uploadPayload: CaptureUploadPayload {
            CaptureUploadPayload(packageURL: packageURL)
        }
    }

    struct CaptureUploadPayload: Codable, Equatable {
        let packageURL: URL
    }

    struct DiscoveredDevice: Identifiable, Equatable {
        let id: String
        let name: String
        let isMock: Bool
    }

    // MARK: - Published Properties

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var captureState: CaptureState = .idle
    @Published private(set) var discoveredDevices: [DiscoveredDevice] = []
    @Published private(set) var currentFrame: UIImage?
    @Published private(set) var streamingInfo: StreamingInfo?
    @Published private(set) var isConnectedToMockDevice: Bool = false
    @Published var useMockDevice: Bool = true // Default to mock for testing
    @Published var mockVideoURL: URL?

    // MARK: - Private Properties

    private var deviceKit: MWDeviceKit?
    private var mockDeviceKit: MWMockDeviceKit?
    private var cameraSession: MWCameraSession?
    private var currentDevice: MWDevice?

    private var currentArtifacts: CaptureArtifacts?
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var frameCount: Int = 0
    private var recordingStartTime: Date?
    private var lastFrameTime: CMTime?

    // Motion tracking
    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.blueprint.glasses.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private var motionLogFileHandle: FileHandle?
    private let motionJSONEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    override init() {
        super.init()
        setupSDK()
    }

    private func setupSDK() {
        // Initialize the MWDAT SDK
        do {
            deviceKit = try MWDeviceKit()
            print("✅ [GlassesCapture] MWDeviceKit initialized")
        } catch {
            print("❌ [GlassesCapture] Failed to initialize MWDeviceKit: \(error)")
            connectionState = .error("Failed to initialize Meta glasses SDK: \(error.localizedDescription)")
        }

        // Initialize MockDeviceKit for testing
        do {
            mockDeviceKit = try MWMockDeviceKit()
            print("✅ [GlassesCapture] MWMockDeviceKit initialized for testing")
        } catch {
            print("⚠️ [GlassesCapture] MockDeviceKit not available: \(error)")
        }
    }

    // MARK: - Device Discovery

    func startScanning() {
        guard connectionState != .scanning else { return }
        connectionState = .scanning
        discoveredDevices = []

        print("🔍 [GlassesCapture] Starting device scan (useMockDevice: \(useMockDevice))")

        if useMockDevice {
            // Use MockDeviceKit for testing
            startMockDeviceScan()
        } else {
            // Use real DeviceKit for production
            startRealDeviceScan()
        }
    }

    private func startMockDeviceScan() {
        guard let mockKit = mockDeviceKit else {
            connectionState = .error("MockDeviceKit not available")
            return
        }

        // Create a mock device for testing
        Task {
            do {
                // Add simulated discovery delay for realistic UX
                try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

                let mockDevice = DiscoveredDevice(
                    id: "mock-rayban-meta-001",
                    name: "Ray-Ban Meta (Mock)",
                    isMock: true
                )

                await MainActor.run {
                    self.discoveredDevices = [mockDevice]
                    print("✅ [GlassesCapture] Mock device discovered: \(mockDevice.name)")
                }
            } catch {
                await MainActor.run {
                    self.connectionState = .error("Mock scan failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func startRealDeviceScan() {
        guard let kit = deviceKit else {
            connectionState = .error("DeviceKit not initialized")
            return
        }

        Task {
            do {
                // Start scanning for real Meta glasses
                let devices = try await kit.discoverDevices()

                await MainActor.run {
                    self.discoveredDevices = devices.map { device in
                        DiscoveredDevice(
                            id: device.identifier,
                            name: device.name,
                            isMock: false
                        )
                    }
                    print("✅ [GlassesCapture] Found \(self.discoveredDevices.count) devices")
                }
            } catch {
                await MainActor.run {
                    self.connectionState = .error("Device scan failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func stopScanning() {
        connectionState = .disconnected
        discoveredDevices = []
        print("🛑 [GlassesCapture] Stopped scanning")
    }

    // MARK: - Device Connection

    func connect(to device: DiscoveredDevice) {
        guard connectionState != .connecting else { return }
        connectionState = .connecting

        print("🔗 [GlassesCapture] Connecting to: \(device.name)")

        if device.isMock {
            connectToMockDevice(device)
        } else {
            connectToRealDevice(device)
        }
    }

    private func connectToMockDevice(_ device: DiscoveredDevice) {
        guard let mockKit = mockDeviceKit else {
            connectionState = .error("MockDeviceKit not available")
            return
        }

        Task {
            do {
                // Simulate connection delay
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

                // Create mock camera session and attach any configured mock video
                let mockSession = try mockKit.createMockCameraSession(mockVideoURL: self.mockVideoURL)

                await MainActor.run {
                    self.cameraSession = mockSession
                    self.connectionState = .connected(deviceName: device.name)
                    self.isConnectedToMockDevice = true
                    print("✅ [GlassesCapture] Connected to mock device: \(device.name)")
                }
            } catch {
                await MainActor.run {
                    self.connectionState = .error("Mock connection failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func connectToRealDevice(_ device: DiscoveredDevice) {
        guard let kit = deviceKit else {
            connectionState = .error("DeviceKit not initialized")
            return
        }

        Task {
            do {
                // Connect to the real device
                let connectedDevice = try await kit.connect(deviceId: device.id)
                self.currentDevice = connectedDevice

                // Create camera session
                let session = try await connectedDevice.createCameraSession()

                await MainActor.run {
                    self.cameraSession = session
                    self.connectionState = .connected(deviceName: device.name)
                    self.isConnectedToMockDevice = false
                    print("✅ [GlassesCapture] Connected to device: \(device.name)")
                }
            } catch {
                await MainActor.run {
                    self.connectionState = .error("Connection failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func disconnect() {
        if captureState.isActive {
            stopCapture()
        }

        cameraSession = nil
        currentDevice = nil
        isConnectedToMockDevice = false
        connectionState = .disconnected
        print("🔌 [GlassesCapture] Disconnected")
    }

    // MARK: - Mock Video Source

    func updateMockVideoURL(_ url: URL) {
        mockVideoURL = url

        if cameraSession?.isMockSession == true {
            cameraSession?.setMockVideoURL(url)
        }
    }

    // MARK: - Video Capture

    func startCapture() {
        guard case .connected = connectionState else {
            captureState = .error("Not connected to a device")
            return
        }

        guard captureState == .idle else {
            print("⚠️ [GlassesCapture] Capture already active")
            return
        }

        captureState = .preparing
        print("⏺️ [GlassesCapture] Starting capture...")

        Task {
            do {
                // Prepare capture artifacts
                let artifacts = try prepareArtifacts()
                currentArtifacts = artifacts

                // Setup video writer
                try setupVideoWriter(artifacts: artifacts)

                // Setup motion logging
                setupMotionLogging(artifacts: artifacts)

                // Start camera stream
                try await startCameraStream()

                await MainActor.run {
                    self.recordingStartTime = Date()
                    self.frameCount = 0
                    self.captureState = .streaming(StreamingInfo(
                        startedAt: Date(),
                        frameCount: 0,
                        resolution: CGSize(width: 1280, height: 720), // 720p
                        fps: 30.0,
                        durationSeconds: 0
                    ))
                    print("✅ [GlassesCapture] Capture started")
                }
            } catch {
                await MainActor.run {
                    self.captureState = .error("Failed to start capture: \(error.localizedDescription)")
                }
            }
        }
    }

    private func prepareArtifacts() throws -> CaptureArtifacts {
        let baseName = "glasses-capture-\(UUID().uuidString)"
        let tempDir = FileManager.default.temporaryDirectory
        let recordingDir = tempDir.appendingPathComponent(baseName, isDirectory: true)
        let framesDir = recordingDir.appendingPathComponent("frames", isDirectory: true)
        let packageURL = recordingDir.deletingLastPathComponent().appendingPathComponent("\(baseName).zip")
        let videoURL = recordingDir.appendingPathComponent("walkthrough.mov")
        let motionURL = recordingDir.appendingPathComponent("motion.jsonl")
        let manifestURL = recordingDir.appendingPathComponent("manifest.json")

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: recordingDir.path) {
            try fileManager.removeItem(at: recordingDir)
        }
        try fileManager.createDirectory(at: recordingDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: framesDir, withIntermediateDirectories: true)

        return CaptureArtifacts(
            baseFilename: baseName,
            directoryURL: recordingDir,
            videoURL: videoURL,
            framesDirectoryURL: framesDir,
            motionLogURL: motionURL,
            manifestURL: manifestURL,
            packageURL: packageURL,
            startedAt: Date(),
            endedAt: Date(), // Will be updated on stop
            frameCount: 0,
            durationSeconds: 0
        )
    }

    private func setupVideoWriter(artifacts: CaptureArtifacts) throws {
        // Setup AVAssetWriter for 720p @ 30fps
        let writer = try AVAssetWriter(outputURL: artifacts.videoURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1280,
            AVVideoHeightKey: 720,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000, // 8 Mbps for good quality
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 1280,
                kCVPixelBufferHeightKey as String: 720
            ]
        )

        guard writer.canAdd(input) else {
            throw NSError(domain: "GlassesCapture", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Cannot add video input to writer"
            ])
        }

        writer.add(input)

        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "GlassesCapture", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to start writing"
            ])
        }

        writer.startSession(atSourceTime: .zero)

        self.videoWriter = writer
        self.videoWriterInput = input
        self.pixelBufferAdaptor = adaptor
        self.lastFrameTime = .zero
    }

    private func setupMotionLogging(artifacts: CaptureArtifacts) {
        do {
            if FileManager.default.fileExists(atPath: artifacts.motionLogURL.path) {
                try FileManager.default.removeItem(at: artifacts.motionLogURL)
            }
            FileManager.default.createFile(atPath: artifacts.motionLogURL.path, contents: nil)
            motionLogFileHandle = try FileHandle(forWritingTo: artifacts.motionLogURL)

            // Start motion updates
            if motionManager.isDeviceMotionAvailable {
                motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
                motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
                    guard let self, let motion else { return }
                    self.writeMotionSample(motion)
                }
            }

            print("✅ [GlassesCapture] Motion logging started")
        } catch {
            print("⚠️ [GlassesCapture] Failed to setup motion logging: \(error)")
        }
    }

    private func writeMotionSample(_ motion: CMDeviceMotion) {
        guard currentArtifacts != nil else { return }

        let sample: [String: Any] = [
            "timestamp": motion.timestamp,
            "wallTime": ISO8601DateFormatter().string(from: Date()),
            "attitude": [
                "roll": motion.attitude.roll,
                "pitch": motion.attitude.pitch,
                "yaw": motion.attitude.yaw,
                "quaternion": [
                    "x": motion.attitude.quaternion.x,
                    "y": motion.attitude.quaternion.y,
                    "z": motion.attitude.quaternion.z,
                    "w": motion.attitude.quaternion.w
                ]
            ],
            "rotationRate": [
                "x": motion.rotationRate.x,
                "y": motion.rotationRate.y,
                "z": motion.rotationRate.z
            ],
            "gravity": [
                "x": motion.gravity.x,
                "y": motion.gravity.y,
                "z": motion.gravity.z
            ],
            "userAcceleration": [
                "x": motion.userAcceleration.x,
                "y": motion.userAcceleration.y,
                "z": motion.userAcceleration.z
            ]
        ]

        if let data = try? JSONSerialization.data(withJSONObject: sample),
           let handle = motionLogFileHandle {
            handle.write(data)
            if let newline = "\n".data(using: .utf8) {
                handle.write(newline)
            }
        }
    }

    private func startCameraStream() async throws {
        guard let session = cameraSession else {
            throw NSError(domain: "GlassesCapture", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "Camera session not available"
            ])
        }

        // Configure stream for maximum quality (720p @ 30fps)
        let streamConfig = MWCameraStreamConfig(
            resolution: .hd720p,
            frameRate: 30,
            format: .bgra
        )

        // Start streaming with frame handler
        try await session.startStreaming(config: streamConfig) { [weak self] frame in
            guard let self else { return }
            Task { @MainActor in
                self.handleFrame(frame)
            }
        }
    }

    private func handleFrame(_ frame: MWCameraFrame) {
        guard case .streaming = captureState else { return }

        frameCount += 1

        // Convert frame to UIImage for preview
        if let image = frame.toUIImage() {
            currentFrame = image
        }

        // Write frame to video
        writeVideoFrame(frame)

        // Update streaming info
        if let startTime = recordingStartTime {
            let duration = Date().timeIntervalSince(startTime)
            streamingInfo = StreamingInfo(
                startedAt: startTime,
                frameCount: frameCount,
                resolution: CGSize(width: frame.width, height: frame.height),
                fps: Double(frameCount) / max(duration, 0.001),
                durationSeconds: duration
            )
            captureState = .streaming(streamingInfo!)
        }

        // Log progress every 30 frames (1 second at 30fps)
        if frameCount % 30 == 0 {
            print("📹 [GlassesCapture] Frames captured: \(frameCount)")
        }
    }

    private func writeVideoFrame(_ frame: MWCameraFrame) {
        guard let input = videoWriterInput,
              let adaptor = pixelBufferAdaptor,
              input.isReadyForMoreMediaData,
              let pixelBuffer = frame.toPixelBuffer() else {
            return
        }

        let frameTime = CMTime(seconds: Double(frameCount) / 30.0, preferredTimescale: 600)
        adaptor.append(pixelBuffer, withPresentationTime: frameTime)
        lastFrameTime = frameTime
    }

    func pauseCapture() {
        guard case .streaming = captureState else { return }
        cameraSession?.pauseStreaming()
        captureState = .paused
        print("⏸️ [GlassesCapture] Capture paused")
    }

    func resumeCapture() {
        guard captureState == .paused else { return }
        cameraSession?.resumeStreaming()
        if let info = streamingInfo {
            captureState = .streaming(info)
        }
        print("▶️ [GlassesCapture] Capture resumed")
    }

    func stopCapture() {
        guard captureState.isActive else { return }

        print("⏹️ [GlassesCapture] Stopping capture...")

        // Stop camera stream
        cameraSession?.stopStreaming()

        // Stop motion updates
        motionManager.stopDeviceMotionUpdates()

        // Close motion log
        if let handle = motionLogFileHandle {
            try? handle.close()
            motionLogFileHandle = nil
        }

        // Finish video writing
        guard let writer = videoWriter,
              let input = videoWriterInput,
              var artifacts = currentArtifacts else {
            captureState = .idle
            return
        }

        input.markAsFinished()

        Task {
            await writer.finishWriting()

            let endedAt = Date()
            let duration = recordingStartTime.map { endedAt.timeIntervalSince($0) } ?? 0

            // Update artifacts with final values
            let finalArtifacts = CaptureArtifacts(
                baseFilename: artifacts.baseFilename,
                directoryURL: artifacts.directoryURL,
                videoURL: artifacts.videoURL,
                framesDirectoryURL: artifacts.framesDirectoryURL,
                motionLogURL: artifacts.motionLogURL,
                manifestURL: artifacts.manifestURL,
                packageURL: artifacts.packageURL,
                startedAt: artifacts.startedAt,
                endedAt: endedAt,
                frameCount: frameCount,
                durationSeconds: duration
            )

            // Write manifest
            await writeManifest(artifacts: finalArtifacts)

            // Package artifacts
            await packageArtifacts(finalArtifacts)

            await MainActor.run {
                self.currentArtifacts = finalArtifacts
                self.captureState = .finished(finalArtifacts)
                self.videoWriter = nil
                self.videoWriterInput = nil
                self.pixelBufferAdaptor = nil
                self.recordingStartTime = nil
                self.frameCount = 0
                print("✅ [GlassesCapture] Capture finished: \(finalArtifacts.frameCount) frames, \(String(format: "%.1f", finalArtifacts.durationSeconds))s")
            }
        }
    }

    private func writeManifest(artifacts: CaptureArtifacts) async {
        // GPU Pipeline-compatible manifest schema
        // Required fields: scene_id, device_model, os_version, fps_source, width, height, capture_start_epoch_ms, has_lidar
        let manifest: [String: Any] = [
            // Required fields for pipeline trigger
            "scene_id": "",  // Will be patched by upload service with targetId/reservationId
            "video_uri": "", // Will be patched by upload service with full GCS path
            "device_model": "Meta Ray-Ban Smart Glasses",
            "os_version": UIDevice.current.systemVersion,
            "fps_source": 30.0,  // Pipeline expects float
            "width": 1280,
            "height": 720,
            "capture_start_epoch_ms": Int64(artifacts.startedAt.timeIntervalSince1970 * 1000),
            "has_lidar": false,  // Glasses don't have LiDAR

            // Optional fields that enhance processing
            "scale_hint_m_per_unit": 1.0,
            "intended_space_type": "indoor",

            // Additional metadata (not required by pipeline but useful)
            "capture_source": "glasses",
            "capture_end_epoch_ms": Int64(artifacts.endedAt.timeIntervalSince1970 * 1000),
            "duration_seconds": artifacts.durationSeconds,
            "frame_count": artifacts.frameCount,
            "has_motion_data": FileManager.default.fileExists(atPath: artifacts.motionLogURL.path)
        ]

        if let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .withoutEscapingSlashes]) {
            try? data.write(to: artifacts.manifestURL, options: .atomic)
        }
    }

    private func packageArtifacts(_ artifacts: CaptureArtifacts) async {
        // Package as ZIP for upload
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: artifacts.packageURL.path) {
            try? fileManager.removeItem(at: artifacts.packageURL)
        }

        // Use ZIPFoundation if available, otherwise skip packaging
        #if canImport(ZIPFoundation)
      //  import ZIPFoundation
        try? fileManager.zipItem(at: artifacts.directoryURL, to: artifacts.packageURL, shouldKeepParent: true)
        #else
        print("⚠️ [GlassesCapture] ZIPFoundation not available, skipping packaging")
        #endif
    }

    // MARK: - Photo Capture (for scale anchors)

    func capturePhoto() async throws -> UIImage {
        guard case .connected = connectionState,
              let session = cameraSession else {
            throw NSError(domain: "GlassesCapture", code: -4, userInfo: [
                NSLocalizedDescriptionKey: "Not connected to device"
            ])
        }

        let photo = try await session.capturePhoto()

        if let image = photo.toUIImage() {
            return image
        }

        throw NSError(domain: "GlassesCapture", code: -5, userInfo: [
            NSLocalizedDescriptionKey: "Failed to convert photo to image"
        ])
    }

    // MARK: - Cleanup

    func reset() {
        stopCapture()
        disconnect()
        currentArtifacts = nil
        currentFrame = nil
        streamingInfo = nil
        captureState = .idle
    }
}

// MARK: - Mock/Placeholder Types for SDK Integration

// These types provide a working implementation for testing
// When the actual MWDAT SDK is available, these will be replaced by real SDK types

/// Placeholder for MWDeviceKit - handles device discovery
class MWDeviceKit {
    init() throws {
        // Real SDK initialization
    }

    func discoverDevices() async throws -> [MWDevice] {
        // Placeholder - real SDK provides actual discovery
        return []
    }

    func connect(deviceId: String) async throws -> MWDevice {
        throw NSError(domain: "MWDAT", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Real device connection requires Meta DAT SDK"
        ])
    }
}

/// Placeholder for MWMockDeviceKit - provides mock device for testing
class MWMockDeviceKit {
    init() throws {
        // MockDeviceKit initialization
    }

    func createMockCameraSession(mockVideoURL: URL? = nil) throws -> MWCameraSession {
        let session = MWCameraSession(isMock: true)
        if let mockVideoURL {
            session.setMockVideoURL(mockVideoURL)
        }
        return session
    }
}

/// Placeholder for MWDevice
class MWDevice {
    let identifier: String
    let name: String

    init(identifier: String, name: String) {
        self.identifier = identifier
        self.name = name
    }

    func createCameraSession() async throws -> MWCameraSession {
        return MWCameraSession(isMock: false)
    }
}

/// Camera stream configuration
struct MWCameraStreamConfig {
    enum Resolution {
        case hd720p
        case hd1080p
    }

    enum Format {
        case bgra
        case yuv
    }

    let resolution: Resolution
    let frameRate: Int
    let format: Format
}

/// Camera session for streaming video from glasses
class MWCameraSession {
    private let isMock: Bool
    private var isStreaming = false
    private var frameHandler: ((MWCameraFrame) -> Void)?
    private var frameTimer: Timer?
    private var mockVideoURL: URL?
    private var mockPlaybackWorkItem: DispatchWorkItem?
    private let streamingQueue = DispatchQueue(label: "com.blueprint.glasses.mockstream")
    private var lastStreamConfig: MWCameraStreamConfig?
    private var lastHandler: ((MWCameraFrame) -> Void)?

    init(isMock: Bool) {
        self.isMock = isMock
    }

    func startStreaming(config: MWCameraStreamConfig, handler: @escaping (MWCameraFrame) -> Void) async throws {
        guard !isStreaming else { return }
        isStreaming = true
        frameHandler = handler
        lastHandler = handler
        lastStreamConfig = config

        if isMock {
            startMockStreaming(with: config, handler: handler)
        }
        // Real SDK would connect to actual glasses camera stream
    }

    func pauseStreaming() {
        frameTimer?.invalidate()
        mockPlaybackWorkItem?.cancel()
        isStreaming = false
    }

    func resumeStreaming() {
        guard !isStreaming, let handler = lastHandler, let config = lastStreamConfig else { return }
        isStreaming = true

        if isMock {
            startMockStreaming(with: config, handler: handler)
        }
    }

    func stopStreaming() {
        frameTimer?.invalidate()
        frameTimer = nil
        mockPlaybackWorkItem?.cancel()
        mockPlaybackWorkItem = nil
        isStreaming = false
        frameHandler = nil
        lastStreamConfig = nil
        lastHandler = nil
    }

    func capturePhoto() async throws -> MWCameraPhoto {
        return MWCameraPhoto()
    }

    func setMockVideoURL(_ url: URL) {
        mockVideoURL = url
    }

    var isMockSession: Bool { isMock }

    // MARK: - Mock Streaming Helpers

    private func startMockStreaming(with config: MWCameraStreamConfig, handler: @escaping (MWCameraFrame) -> Void) {
        if let mockVideoURL {
            startMockVideoPlayback(url: mockVideoURL, config: config, handler: handler)
        } else {
            startMockGradientTimer(frameRate: config.frameRate, handler: handler)
        }
    }

    private func startMockGradientTimer(frameRate: Int, handler: @escaping (MWCameraFrame) -> Void) {
        let interval = 1.0 / Double(frameRate)
        frameTimer?.invalidate()

        Task { @MainActor in
            self.frameTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                guard let self, self.isStreaming else { return }
                let frame = MWCameraFrame(width: 1280, height: 720, timestamp: Date())
                handler(frame)
            }
        }
    }

    private func startMockVideoPlayback(url: URL, config: MWCameraStreamConfig, handler: @escaping (MWCameraFrame) -> Void) {
        mockPlaybackWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }

            while self.isStreaming {
                let asset = AVAsset(url: url)
                guard let track = asset.tracks(withMediaType: .video).first else { break }

                do {
                    let reader = try AVAssetReader(asset: asset)
                    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                    ])
                    if reader.canAdd(output) {
                        reader.add(output)
                    }

                    guard reader.startReading() else { break }

                    let frameDuration = 1.0 / Double(config.frameRate)

                    while self.isStreaming, reader.status == .reading {
                        if let sampleBuffer = output.copyNextSampleBuffer(),
                           let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                            autoreleasepool {
                                let frame = MWCameraFrame(pixelBuffer: buffer, timestamp: Date())
                                handler(frame)
                            }

                            Thread.sleep(forTimeInterval: frameDuration)
                        } else {
                            break
                        }
                    }

                    reader.cancelReading()

                    if !self.isStreaming { break }
                    // Loop the mock video for continuous streaming
                } catch {
                    print("⚠️ [MockCameraSession] Failed to read mock video: \(error)")
                    break
                }
            }
        }

        mockPlaybackWorkItem = workItem
        streamingQueue.async(execute: workItem)
    }
}

/// Represents a single frame from the glasses camera
struct MWCameraFrame {
    let width: Int
    let height: Int
    let timestamp: Date

    private static let ciContext = CIContext()
    let pixelBuffer: CVPixelBuffer?

    init(width: Int = 1280, height: Int = 720, timestamp: Date = Date(), pixelBuffer: CVPixelBuffer? = nil) {
        self.width = width
        self.height = height
        self.timestamp = timestamp
        self.pixelBuffer = pixelBuffer
    }

    init(pixelBuffer: CVPixelBuffer, timestamp: Date = Date()) {
        self.pixelBuffer = pixelBuffer
        self.width = CVPixelBufferGetWidth(pixelBuffer)
        self.height = CVPixelBufferGetHeight(pixelBuffer)
        self.timestamp = timestamp
    }

    func toUIImage() -> UIImage? {
        if let pixelBuffer,
           let cgImage = MWCameraFrame.ciContext.createCGImage(CIImage(cvPixelBuffer: pixelBuffer), from: CIImage(cvPixelBuffer: pixelBuffer).extent) {
            return UIImage(cgImage: cgImage)
        }

        // Generate a mock frame with gradient and timestamp
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let cgContext = context.cgContext

            // Create animated gradient based on timestamp
            let hue = CGFloat(timestamp.timeIntervalSince1970.truncatingRemainder(dividingBy: 10.0)) / 10.0
            let color1 = UIColor(hue: hue, saturation: 0.7, brightness: 0.8, alpha: 1.0)
            let color2 = UIColor(hue: (hue + 0.5).truncatingRemainder(dividingBy: 1.0), saturation: 0.6, brightness: 0.6, alpha: 1.0)

            let colors = [color1.cgColor, color2.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            // Draw "MOCK" label
            let mockLabel = "MOCK GLASSES FEED"
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 28),
                .foregroundColor: UIColor.white.withAlphaComponent(0.8)
            ]
            let labelSize = mockLabel.size(withAttributes: labelAttrs)
            let labelPoint = CGPoint(
                x: (size.width - labelSize.width) / 2,
                y: size.height / 2 - labelSize.height / 2
            )
            mockLabel.draw(at: labelPoint, withAttributes: labelAttrs)

            // Draw timestamp
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm:ss.SSS"
            let timestamp = timeFormatter.string(from: self.timestamp)
            let timeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 18, weight: .medium),
                .foregroundColor: UIColor.white
            ]
            timestamp.draw(at: CGPoint(x: 20, y: 20), withAttributes: timeAttrs)

            // Draw resolution info
            let resInfo = "\(width)x\(height) @ 30fps"
            let resAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.white.withAlphaComponent(0.7)
            ]
            let resSize = resInfo.size(withAttributes: resAttrs)
            resInfo.draw(at: CGPoint(x: size.width - resSize.width - 20, y: 20), withAttributes: resAttrs)

            // Draw glasses icon indicator
            let glassesIcon = "👓"
            let iconAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 40)
            ]
            glassesIcon.draw(at: CGPoint(x: 20, y: size.height - 60), withAttributes: iconAttrs)
        }
    }

    func toPixelBuffer() -> CVPixelBuffer? {
        if let pixelBuffer {
            return pixelBuffer
        }

        guard let image = toUIImage(), let cgImage = image.cgImage else { return nil }

        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )

        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }
}

/// Represents a captured photo from the glasses
struct MWCameraPhoto {
    func toUIImage() -> UIImage? {
        // Generate a placeholder photo
        let size = CGSize(width: 1280, height: 720)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let label = "PHOTO CAPTURE"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 32),
                .foregroundColor: UIColor.white
            ]
            let labelSize = label.size(withAttributes: attrs)
            label.draw(
                at: CGPoint(x: (size.width - labelSize.width) / 2, y: (size.height - labelSize.height) / 2),
                withAttributes: attrs
            )
        }
    }
}
