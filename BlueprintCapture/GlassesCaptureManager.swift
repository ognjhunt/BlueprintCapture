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
    private static let logPrefix = "[BlueprintGlasses]"

    // MARK: - Types

    enum ConnectionState: Equatable {
        case disconnected
        case registering
        case waitingForDevice
        case permissionRequired(deviceName: String)
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
        #if canImport(MWDATCore)
        let datIdentifier: DeviceIdentifier?
        #endif
    }

    // MARK: - Published Properties

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var captureState: CaptureState = .idle
    @Published private(set) var discoveredDevices: [DiscoveredDevice] = []
    @Published private(set) var currentFrame: UIImage?
    @Published private(set) var streamingInfo: StreamingInfo?
    @Published private(set) var isConnectedToMockDevice: Bool = false
    @Published var useMockDevice: Bool = false
    @Published var mockVideoURL: URL?

    // MARK: - Private Properties

    private var mockDeviceKit: MWMockDeviceKit?
    private var cameraSession: MWCameraSession?
    #if canImport(MWDATCore)
    private let wearables: WearablesInterface = Wearables.shared
    private var registrationTask: Task<Void, Never>?
    private var devicesTask: Task<Void, Never>?
    private var registrationState: RegistrationState = Wearables.shared.registrationState
    private var streamSession: StreamSession?
    private var selectedDevice: DiscoveredDevice?
    private var stateListenerToken: AnyListenerToken?
    private var videoFrameListenerToken: AnyListenerToken?
    private var errorListenerToken: AnyListenerToken?
    private var photoDataListenerToken: AnyListenerToken?
    private var pendingPhotoContinuation: CheckedContinuation<UIImage, Error>?
    #endif

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

    // The curated jobId we are currently capturing for (used for local organization only).
    private var currentJobId: String?

    // Persist last connected device to make reconnect 1-tap.
    private let lastDeviceIdKey = "com.blueprint.glasses.lastDeviceId"
    private let lastDeviceNameKey = "com.blueprint.glasses.lastDeviceName"
    private let lastDeviceIsMockKey = "com.blueprint.glasses.lastDeviceIsMock"

    // MARK: - Initialization

    override init() {
        super.init()
        setupSDK()
    }

    private func setupSDK() {
        // Initialize MockDeviceKit for testing
        do {
            mockDeviceKit = try MWMockDeviceKit()
            print("\(Self.logPrefix) mockDeviceKit initialized")
        } catch {
            print("\(Self.logPrefix) mockDeviceKit unavailable: \(error)")
        }

        #if canImport(MWDATCore)
        registrationState = wearables.registrationState
        print("\(Self.logPrefix) initial registrationState=\(registrationState)")
        startWearablesObservers()
        syncConnectionStateFromWearables()
        #endif
    }

    // MARK: - Device Discovery

    func startScanning() {
        print("\(Self.logPrefix) beginMetaSetup useMockDevice=\(useMockDevice)")

        if useMockDevice {
            discoveredDevices = []
            // Use MockDeviceKit for testing
            startMockDeviceScan()
        } else {
            #if canImport(MWDATCore)
            if registrationState == .registered {
                syncConnectionStateFromWearables(forceRefresh: true)
            } else {
                connectionState = .registering
                Task {
                    do {
                        try wearables.startRegistration()
                        print("\(Self.logPrefix) wearables.startRegistration launched")
                    } catch let error as RegistrationError {
                        await MainActor.run {
                            print("\(Self.logPrefix) wearables.startRegistration failed: \(error.description)")
                            self.connectionState = .error(error.description)
                        }
                    } catch {
                        await MainActor.run {
                            print("\(Self.logPrefix) wearables.startRegistration failed: \(error.localizedDescription)")
                            self.connectionState = .error(error.localizedDescription)
                        }
                    }
                }
            }
            #else
            connectionState = .error("Meta DAT SDK is unavailable in this build.")
            #endif
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

                #if canImport(MWDATCore)
                let mockDevice = DiscoveredDevice(
                    id: "mock-rayban-meta-001",
                    name: "Ray-Ban Meta (Mock)",
                    isMock: true,
                    datIdentifier: nil
                )
                #else
                let mockDevice = DiscoveredDevice(
                    id: "mock-rayban-meta-001",
                    name: "Ray-Ban Meta (Mock)",
                    isMock: true
                )
                #endif

                await MainActor.run {
                    self.discoveredDevices = [mockDevice]
                    self.connectionState = .waitingForDevice
                    print("\(Self.logPrefix) mock device discovered name=\(mockDevice.name)")
                }
            } catch {
                await MainActor.run {
                    print("\(Self.logPrefix) mock scan failed: \(error.localizedDescription)")
                    self.connectionState = .error("Mock scan failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func stopScanning() {
        #if canImport(MWDATCore)
        if useMockDevice {
            connectionState = .disconnected
            discoveredDevices = []
        } else {
            syncConnectionStateFromWearables(forceRefresh: true)
        }
        #else
        connectionState = .disconnected
        discoveredDevices = []
        #endif
        print("\(Self.logPrefix) stoppedMetaSetup")
    }

    // MARK: - Device Connection

    func connect(to device: DiscoveredDevice) {
        guard connectionState != .connecting else { return }
        connectionState = .connecting

        print("\(Self.logPrefix) connect requested device=\(device.name) isMock=\(device.isMock)")

        if device.isMock {
            connectToMockDevice(device)
        } else {
            #if canImport(MWDATCore)
            connectToRealDevice(device)
            #else
            connectionState = .error("Meta DAT SDK is unavailable in this build.")
            #endif
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
                    self.persistLastConnectedDevice(device)
                    print("\(Self.logPrefix) connected mock device=\(device.name)")
                }
            } catch {
                await MainActor.run {
                    print("\(Self.logPrefix) mock connection failed: \(error.localizedDescription)")
                    self.connectionState = .error("Mock connection failed: \(error.localizedDescription)")
                }
            }
        }
    }

    #if canImport(MWDATCore)
    private func connectToRealDevice(_ device: DiscoveredDevice) {
        Task {
            do {
                guard let datIdentifier = device.datIdentifier ?? discoveredDevices.first(where: { $0.id == device.id })?.datIdentifier else {
                    await MainActor.run {
                        self.connectionState = .error("This device is not available through Meta DAT yet. Complete setup in Meta AI first.")
                    }
                    return
                }

                let status = try await wearables.checkPermissionStatus(.camera)
                print("\(Self.logPrefix) cameraPermissionStatus=\(status) device=\(device.name)")
                let grantedStatus: PermissionStatus
                if status == .granted {
                    grantedStatus = status
                } else {
                    let requested = try await wearables.requestPermission(.camera)
                    print("\(Self.logPrefix) cameraPermissionRequested result=\(requested) device=\(device.name)")
                    grantedStatus = requested
                }

                guard grantedStatus == .granted else {
                    await MainActor.run {
                        self.connectionState = .permissionRequired(deviceName: device.name)
                    }
                    return
                }

                let selector = SpecificDeviceSelector(device: datIdentifier)
                let config = StreamSessionConfig(
                    videoCodec: .raw,
                    resolution: .low,
                    frameRate: 24
                )
                let session = StreamSession(streamSessionConfig: config, deviceSelector: selector)
                await MainActor.run {
                    self.selectedDevice = device
                    self.installStreamListeners(session)
                    self.streamSession = session
                    self.connectionState = .connected(deviceName: device.name)
                    self.isConnectedToMockDevice = false
                    self.persistLastConnectedDevice(device)
                    print("\(Self.logPrefix) connected dat device=\(device.name)")
                }
            } catch let error as RegistrationError {
                await MainActor.run {
                    print("\(Self.logPrefix) dat connect registration error: \(error.description)")
                    self.connectionState = .error(error.description)
                }
            } catch {
                await MainActor.run {
                    print("\(Self.logPrefix) dat connect failed: \(error.localizedDescription)")
                    self.connectionState = .error("Connection failed: \(error.localizedDescription)")
                }
            }
        }
    }
    #endif

    func disconnect() {
        if captureState.isActive {
            stopCapture()
        }

        cameraSession = nil
        #if canImport(MWDATCore)
        Task {
            await self.streamSession?.stop()
        }
        streamSession = nil
        selectedDevice = nil
        stateListenerToken = nil
        videoFrameListenerToken = nil
        errorListenerToken = nil
        photoDataListenerToken = nil
        #endif
        isConnectedToMockDevice = false
        currentFrame = nil
        streamingInfo = nil
        connectionState = .disconnected
        print("\(Self.logPrefix) disconnected")
    }

    // MARK: - Reconnect

    var lastConnectedDevice: DiscoveredDevice? {
        guard let id = UserDefaults.standard.string(forKey: lastDeviceIdKey),
              let name = UserDefaults.standard.string(forKey: lastDeviceNameKey) else {
            return nil
        }
        let isMock = UserDefaults.standard.bool(forKey: lastDeviceIsMockKey)
        #if canImport(MWDATCore)
        return DiscoveredDevice(id: id, name: name, isMock: isMock, datIdentifier: nil)
        #else
        return DiscoveredDevice(id: id, name: name, isMock: isMock)
        #endif
    }

    func reconnectLastDevice() {
        guard let device = lastConnectedDevice else { return }
        // Fast-path reconnect: connect directly if possible.
        if let liveMatch = discoveredDevices.first(where: { $0.id == device.id }) {
            connect(to: liveMatch)
        } else if device.isMock {
            connect(to: device)
        } else {
            startScanning()
        }
    }

    private func persistLastConnectedDevice(_ device: DiscoveredDevice) {
        UserDefaults.standard.set(device.id, forKey: lastDeviceIdKey)
        UserDefaults.standard.set(device.name, forKey: lastDeviceNameKey)
        UserDefaults.standard.set(device.isMock, forKey: lastDeviceIsMockKey)
    }

    #if canImport(MWDATCore)
    private func startWearablesObservers() {
        registrationTask?.cancel()
        devicesTask?.cancel()

        registrationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await state in wearables.registrationStateStream() {
                registrationState = state
                print("\(Self.logPrefix) registrationState=\(state)")
                syncConnectionStateFromWearables()
            }
        }

        devicesTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await deviceIds in wearables.devicesStream() {
                print("\(Self.logPrefix) devices.count=\(deviceIds.count)")
                discoveredDevices = deviceIds.map { deviceId in
                    let name = self.wearables.deviceForIdentifier(deviceId)?.nameOrId() ?? String(describing: deviceId)
                    return DiscoveredDevice(
                        id: String(describing: deviceId),
                        name: name,
                        isMock: false,
                        datIdentifier: deviceId
                    )
                }
                syncConnectionStateFromWearables()
            }
        }
    }

    private func syncConnectionStateFromWearables(forceRefresh: Bool = false) {
        guard !useMockDevice else { return }

        if !forceRefresh {
            switch connectionState {
            case .connected, .connecting, .permissionRequired:
                return
            default:
                break
            }
        }

        switch registrationState {
        case .registering:
            connectionState = .registering
        case .registered:
            connectionState = .waitingForDevice
        default:
            connectionState = .disconnected
        }
        print("\(Self.logPrefix) uiState=\(connectionState) discoveredDevices=\(discoveredDevices.count)")
    }

    private func installStreamListeners(_ session: StreamSession) {
        stateListenerToken = session.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleStreamStateChange(state)
            }
        }
        videoFrameListenerToken = session.videoFramePublisher.listen { [weak self] frame in
            Task { @MainActor [weak self] in
                self?.handleDATVideoFrame(frame)
            }
        }
        errorListenerToken = session.errorPublisher.listen { [weak self] error in
            Task { @MainActor [weak self] in
                let message = self?.formatStreamError(error) ?? error.localizedDescription
                print("\(Self.logPrefix) streamError=\(message)")
                self?.connectionState = .error(message)
                if self?.captureState.isActive == true {
                    self?.captureState = .error(message)
                }
            }
        }
        photoDataListenerToken = session.photoDataPublisher.listen { [weak self] photoData in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let image = UIImage(data: photoData.data) {
                    pendingPhotoContinuation?.resume(returning: image)
                } else {
                    pendingPhotoContinuation?.resume(throwing: NSError(
                        domain: "GlassesCapture",
                        code: -5,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to decode the captured photo."]
                    ))
                }
                pendingPhotoContinuation = nil
            }
        }
    }

    private func handleStreamStateChange(_ state: StreamSessionState) {
        print("\(Self.logPrefix) streamState=\(state)")
        switch state {
        case .paused:
            if captureState.isActive {
                captureState = .paused
            }
        case .stopped:
            if case .preparing = captureState {
                captureState = .idle
            }
        default:
            break
        }
    }

    private func handleDATVideoFrame(_ frame: VideoFrame) {
        guard case .streaming = captureState else { return }
        guard let image = frame.makeUIImage() else { return }

        frameCount += 1
        currentFrame = image
        writeVideoFrame(image: image, frameTime: CMTime(seconds: Double(frameCount) / 24.0, preferredTimescale: 600))

        if let startTime = recordingStartTime {
            let duration = Date().timeIntervalSince(startTime)
            let imageSize = image.size
            streamingInfo = StreamingInfo(
                startedAt: startTime,
                frameCount: frameCount,
                resolution: CGSize(width: imageSize.width, height: imageSize.height),
                fps: Double(frameCount) / max(duration, 0.001),
                durationSeconds: duration
            )
            if let streamingInfo {
                captureState = .streaming(streamingInfo)
            }
        }
    }

    private func formatStreamError(_ error: StreamSessionError) -> String {
        switch error {
        case .deviceNotFound:
            return "Meta glasses not found. Open Meta AI and keep them nearby."
        case .deviceNotConnected:
            return "Meta glasses are no longer connected."
        case .permissionDenied:
            return "Camera permission was denied in Meta AI."
        case .timeout:
            return "The glasses connection timed out."
        case .videoStreamingError:
            return "Video streaming failed. Try reconnecting the glasses."
        case .internalError:
            return "The Meta glasses SDK reported an internal error."
        @unknown default:
            return "An unknown Meta glasses error occurred."
        }
    }

    func handleWearablesCallback(_ url: URL) -> Bool {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
        else {
            return false
        }

        Task {
            do {
                print("\(Self.logPrefix) handleWearablesCallback url=\(url.absoluteString)")
                _ = try await wearables.handleUrl(url)
            } catch let error as RegistrationError {
                await MainActor.run {
                    print("\(Self.logPrefix) handleWearablesCallback failed: \(error.description)")
                    self.connectionState = .error(error.description)
                }
            } catch {
                await MainActor.run {
                    print("\(Self.logPrefix) handleWearablesCallback failed: \(error.localizedDescription)")
                    self.connectionState = .error(error.localizedDescription)
                }
            }
        }
        return true
    }
    #endif

    #if !canImport(MWDATCore)
    func handleWearablesCallback(_ url: URL) -> Bool {
        false
    }
    #endif

    // MARK: - Mock Video Source

    func updateMockVideoURL(_ url: URL) {
        mockVideoURL = url

        if cameraSession?.isMockSession == true {
            cameraSession?.setMockVideoURL(url)
        }
    }

    // MARK: - Video Capture

    /// Starts a capture for a specific scan job. This does not change upload behavior; it only
    /// helps keep local artifact directories organized by jobId.
    func startCapture(jobId: String) {
        currentJobId = jobId
        startCapture()
    }

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
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let root = appSupport.appendingPathComponent("BlueprintCapture", isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
        let parentDir: URL = {
            if let jobId = currentJobId, !jobId.isEmpty {
                return root.appendingPathComponent(jobId, isDirectory: true)
            }
            return root
        }()
        let recordingDir = parentDir.appendingPathComponent(baseName, isDirectory: true)
        let framesDir = recordingDir.appendingPathComponent("frames", isDirectory: true)
        // Always use directory upload (not ZIP) to ensure manifest.json gets patched
        // with scene_id and video_uri by CaptureUploadService during upload.
        // ZIP uploads skip manifest patching which breaks downstream pipeline.
        let packageURL = recordingDir
        let videoURL = recordingDir.appendingPathComponent("walkthrough.mov")
        let motionURL = recordingDir.appendingPathComponent("motion.jsonl")
        let manifestURL = recordingDir.appendingPathComponent("manifest.json")

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
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

    private func writeVideoFrame(image: UIImage, frameTime: CMTime) {
        guard let input = videoWriterInput,
              let adaptor = pixelBufferAdaptor,
              input.isReadyForMoreMediaData,
              let pixelBuffer = image.toPixelBuffer(width: 1280, height: 720) else {
            return
        }
        adaptor.append(pixelBuffer, withPresentationTime: frameTime)
        lastFrameTime = frameTime
    }

    private func setupMotionLogging(artifacts: CaptureArtifacts) {
        // ⚠️ IMPORTANT: This motion data comes from the PHONE's IMU (CMMotionManager), NOT from
        // the Meta glasses camera. The glasses camera is mounted on the user's head, while the
        // phone may be in the user's pocket or hand.
        //
        // When real Meta DAT SDK integration is available, this should be replaced with
        // glasses-specific IMU data from the MWDAT SDK if available. Until then, treat this as
        // diagnostic-only evidence and not as glasses-mounted camera motion.
        //
        // This phone IMU data is logged for diagnostic purposes only.
        do {
            if FileManager.default.fileExists(atPath: artifacts.motionLogURL.path) {
                try FileManager.default.removeItem(at: artifacts.motionLogURL)
            }
            FileManager.default.createFile(atPath: artifacts.motionLogURL.path, contents: nil)
            motionLogFileHandle = try FileHandle(forWritingTo: artifacts.motionLogURL)

            // Start motion updates from PHONE IMU (not glasses)
            if motionManager.isDeviceMotionAvailable {
                motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
                motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
                    guard let self, let motion else { return }
                    self.writeMotionSample(motion)
                }
            }

            print("✅ [GlassesCapture] Motion logging started (phone IMU, not glasses IMU)")
        } catch {
            print("⚠️ [GlassesCapture] Failed to setup motion logging: \(error)")
        }
    }

    private func writeMotionSample(_ motion: CMDeviceMotion) {
        guard let artifacts = currentArtifacts else { return }

        let sample: [String: Any] = [
            "timestamp": motion.timestamp,
            "t_capture_sec": max(0.0, Date().timeIntervalSince(artifacts.startedAt)),
            "wallTime": ISO8601DateFormatter().string(from: Date()),
            "motion_provenance": "phone_imu_diagnostic_only",
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
        #if canImport(MWDATCamera)
        if let session = streamSession, !isConnectedToMockDevice {
            await session.start()
            return
        }
        #endif

        guard let session = cameraSession else {
            throw NSError(domain: "GlassesCapture", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "Camera session not available"
            ])
        }

        let streamConfig = MWCameraStreamConfig(
            resolution: .hd720p,
            frameRate: 30,
            format: .bgra
        )

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
        #if canImport(MWDATCamera)
        if let session = streamSession, !isConnectedToMockDevice {
            Task { await session.stop() }
        } else {
            cameraSession?.pauseStreaming()
        }
        #else
        cameraSession?.pauseStreaming()
        #endif
        captureState = .paused
        print("⏸️ [GlassesCapture] Capture paused")
    }

    func resumeCapture() {
        guard captureState == .paused else { return }
        #if canImport(MWDATCamera)
        if let session = streamSession, !isConnectedToMockDevice {
            Task { await session.start() }
        } else {
            cameraSession?.resumeStreaming()
        }
        #else
        cameraSession?.resumeStreaming()
        #endif
        if let info = streamingInfo {
            captureState = .streaming(info)
        }
        print("▶️ [GlassesCapture] Capture resumed")
    }

    func stopCapture() {
        guard captureState.isActive else { return }

        print("⏹️ [GlassesCapture] Stopping capture...")

        // Stop camera stream
        #if canImport(MWDATCamera)
        if let session = streamSession, !isConnectedToMockDevice {
            Task { await session.stop() }
        } else {
            cameraSession?.stopStreaming()
        }
        #else
        cameraSession?.stopStreaming()
        #endif

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
                self.currentJobId = nil
                print("✅ [GlassesCapture] Capture finished: \(finalArtifacts.frameCount) frames, \(String(format: "%.1f", finalArtifacts.durationSeconds))s")
            }
        }
    }

    private func writeManifest(artifacts: CaptureArtifacts) async {
        // Raw capture manifest.
        let manifest: [String: Any] = [
            // These are patched by CaptureUploadService during directory upload with actual values.
            "scene_id": "",  // Patched with targetId/reservationId during upload
            "video_uri": "", // Patched with full GCS gs://... path during upload
            "device_model": "Meta Ray-Ban Smart Glasses",
            "os_version": UIDevice.current.systemVersion,
            "fps_source": 30.0,  // Pipeline expects float
            "width": 1280,
            "height": 720,
            "capture_start_epoch_ms": Int64(artifacts.startedAt.timeIntervalSince1970 * 1000),
            "has_lidar": false,  // Glasses don't have LiDAR
            "capture_schema_version": "2.0.0",
            "capture_source": "glasses",
            "capture_tier_hint": "tier2_glasses",

            // Optional fields that enhance processing
            "scale_hint_m_per_unit": 1.0,
            "intended_space_type": "industrial_unknown",

            // Additional metadata (not required by pipeline but useful)
            "capture_end_epoch_ms": Int64(artifacts.endedAt.timeIntervalSince1970 * 1000),
            "duration_seconds": artifacts.durationSeconds,
            "frame_count": artifacts.frameCount
        ]

        if let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .withoutEscapingSlashes]) {
            try? data.write(to: artifacts.manifestURL, options: .atomic)
        }
    }

    private func packageArtifacts(_ artifacts: CaptureArtifacts) async {
        // Directory upload is used (packageURL == directoryURL) to ensure manifest patching works.
        // ZIP packaging is no longer needed since CaptureUploadService patches manifest during
        // directory uploads, but not for ZIP uploads.
        // This function is kept as a no-op for future use if needed.
        print("✅ [GlassesCapture] Artifacts ready for directory upload (manifest will be patched during upload)")
    }

    // MARK: - Photo Capture (for scale anchors)

    func capturePhoto() async throws -> UIImage {
        guard case .connected = connectionState else {
            throw NSError(domain: "GlassesCapture", code: -4, userInfo: [
                NSLocalizedDescriptionKey: "Not connected to device"
            ])
        }

        #if canImport(MWDATCamera)
        if let session = streamSession, !isConnectedToMockDevice {
            return try await withCheckedThrowingContinuation { continuation in
                pendingPhotoContinuation = continuation
                session.capturePhoto(format: .jpeg)
            }
        }
        #endif

        guard let session = cameraSession else {
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

private extension UIImage {
    func toPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        guard let cgImage = cgImage else { return nil }

        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
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
