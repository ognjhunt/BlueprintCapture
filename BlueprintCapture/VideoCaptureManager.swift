import Foundation
import ARKit
import AVFoundation
import Combine
import CoreMotion
import CoreMedia
import Metal
#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

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

    private struct ARFrameLogEntry: Codable {
        let frameIndex: Int
        let timestamp: TimeInterval
        let capturedAt: Date
        let cameraTransform: [Float]
        let intrinsics: [Float]
        let imageResolution: [Int]
        let sceneDepthFile: String?
        let smoothedSceneDepthFile: String?
        let confidenceFile: String?
    }

    @Published private(set) var captureState: CaptureState = .idle
    @Published private(set) var latestUploadPayload: CaptureUploadPayload?

    let session = AVCaptureSession()
    private let arSession = ARSession()

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
        return encoder
    }()

    private var videoDevice: AVCaptureDevice?
    private var currentArtifacts: RecordingArtifacts?
    private var motionLogFileHandle: FileHandle?
    private var arFrameLogFileHandle: FileHandle?
    private var currentCameraIntrinsics: CaptureManifest.CameraIntrinsics?
    private var currentExposureSettings: CaptureManifest.ExposureSettings?
    private var exposureSamples: [CaptureManifest.ExposureSample] = []
    private var exposureTimer: Timer?
    private var currentARKitArtifacts: RecordingArtifacts.ARKitArtifacts?
    private var arFrameCount: Int = 0
    private var exportedMeshAnchors: Set<UUID> = []
    private var isARRunning: Bool = false
    private var shouldSkipARKitOnNextRecording: Bool = false
    private let supportsARCapture: Bool = VideoCaptureManager.evaluateARCaptureSupport()
    private let supportsMeshReconstruction: Bool = VideoCaptureManager.evaluateMeshSupport()

    override init() {
        super.init()
        arSession.delegate = self
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
        guard !session.isRunning else { print("ℹ️ [Capture] startSession ignored — already running"); return }
        DispatchQueue.global(qos: .userInitiated).async {
            print("🎥 [Capture] startRunning() …")
            self.session.startRunning()
            print("🎥 [Capture] session started (isRunning=\(self.session.isRunning))")
        }
    }

    func stopSession() {
        guard session.isRunning else { print("ℹ️ [Capture] stopSession ignored — not running"); return }
        print("🛑 [Capture] stopRunning() …")
        session.stopRunning()
        print("🛑 [Capture] session stopped (isRunning=\(session.isRunning))")
    }

    func startRecording() {
        guard !movieOutput.isRecording else { print("ℹ️ [Capture] startRecording ignored — already recording"); return }
        print("⏺️ [Capture] startRecording begin")
        let baseName = "walkthrough-\(UUID().uuidString)"
        let includeARKit = !shouldSkipARKitOnNextRecording
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
        arFrameCount = 0
        exportedMeshAnchors.removeAll()
        latestUploadPayload = nil
        exposureSamples = []
        currentCameraIntrinsics = videoDevice.map(makeCameraIntrinsics)
        currentExposureSettings = videoDevice.map(makeExposureSettings)
        persistManifest(duration: nil)

        prepareMotionLog(for: artifacts)
        guard motionLogFileHandle != nil else {
            currentArtifacts = nil
            return
        }
        prepareARKitLoggingIfNeeded(for: artifacts)
        startMotionUpdates()
        startExposureLogging()

        movieOutput.startRecording(to: artifacts.videoURL, recordingDelegate: self)
        if !includeARKit && supportsARCapture {
            print("⚠️ [AR] AR session startup skipped due to previous camera conflict; manifest will omit AR data.")
        }
        shouldSkipARKitOnNextRecording = false
        captureState = .recording(artifacts)
        print("⏺️ [Capture] startRecording started → file=\(artifacts.videoURL.lastPathComponent)")
    }

    func stopRecording() {
        guard movieOutput.isRecording else { print("ℹ️ [Capture] stopRecording ignored — not recording"); return }
        print("⏹️ [Capture] stopRecording begin")
        movieOutput.stopRecording()
        stopMotionUpdates()
        stopExposureLogging()
        stopARSession()
        print("⏹️ [Capture] stopRecording requested")
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
        let packageURL = recordingDir.deletingLastPathComponent().appendingPathComponent("\(baseName).zip")
        let videoURL = recordingDir.appendingPathComponent("\(baseName).mov")
        let motionURL = recordingDir.appendingPathComponent("\(baseName)-motion.jsonl")
        let manifestURL = recordingDir.appendingPathComponent("\(baseName)-manifest.json")

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

        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: depth, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: confidence, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: mesh, withIntermediateDirectories: true)
            fileManager.createFile(atPath: frameLog.path, contents: nil)
            return RecordingArtifacts.ARKitArtifacts(
                rootDirectoryURL: root,
                frameLogURL: frameLog,
                depthDirectoryURL: depth,
                confidenceDirectoryURL: confidence,
                meshDirectoryURL: mesh
            )
        } catch {
            print("Failed to set up ARKit capture directories: \(error)")
            return nil
        }
    }

    private func prepareARKitLoggingIfNeeded(for artifacts: RecordingArtifacts) {
        guard let arKit = artifacts.arKit else {
            arFrameLogFileHandle = nil
            return
        }

        do {
            if !FileManager.default.fileExists(atPath: arKit.frameLogURL.path) {
                FileManager.default.createFile(atPath: arKit.frameLogURL.path, contents: nil)
            }
            arFrameLogFileHandle = try FileHandle(forWritingTo: arKit.frameLogURL)
        } catch {
            print("Failed to open ARKit frame log: \(error)")
            arFrameLogFileHandle = nil
            currentARKitArtifacts = nil
        }
    }

    private func startARSessionIfAvailable() {
        guard supportsARCapture, currentARKitArtifacts != nil else {
            if currentARKitArtifacts != nil {
                print("ℹ️ [AR] Capture artifacts prepared but AR session disabled")
            }
            return
        }
        guard !isARRunning else { print("ℹ️ [AR] startSession ignored — already running"); return }

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
        guard currentArtifacts != nil else { return }
        let sample = CaptureManifest.MotionSample(
            timestamp: motion.timestamp,
            wallTime: Date(),
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

    private func writeARFrame(_ frame: ARFrame) {
        guard let artifacts = currentArtifacts, let arKit = artifacts.arKit else { return }
        guard let handle = arFrameLogFileHandle else { return }

        let frameIndex = arFrameCount
        let cameraTransform = matrixToArray(frame.camera.transform)
        let intrinsics = matrixToArray(frame.camera.intrinsics)
        let resolution = [Int(frame.camera.imageResolution.width), Int(frame.camera.imageResolution.height)]

        var sceneDepthFile: String?
        var smoothedDepthFile: String?
        var confidenceFile: String?

        if let depth = frame.sceneDepth, let depthDirectory = arKit.depthDirectoryURL {
            let filename = String(format: "scene-depth-%05d.bin", frameIndex)
            let fileURL = depthDirectory.appendingPathComponent(filename)
            do {
                try writeFloatPixelBuffer(depth.depthMap, to: fileURL)
                sceneDepthFile = relativePath(for: fileURL, relativeTo: artifacts.directoryURL)
            } catch {
                print("Failed to persist scene depth map: \(error)")
            }
        }

        if let smoothedDepth = frame.smoothedSceneDepth, let depthDirectory = arKit.depthDirectoryURL {
            let filename = String(format: "smoothed-depth-%05d.bin", frameIndex)
            let fileURL = depthDirectory.appendingPathComponent(filename)
            do {
                try writeFloatPixelBuffer(smoothedDepth.depthMap, to: fileURL)
                smoothedDepthFile = relativePath(for: fileURL, relativeTo: artifacts.directoryURL)
            } catch {
                print("Failed to persist smoothed depth map: \(error)")
            }
        }

        if let confidenceMap = frame.smoothedSceneDepth?.confidenceMap ?? frame.sceneDepth?.confidenceMap,
           let confidenceDirectory = arKit.confidenceDirectoryURL {
            let filename = String(format: "confidence-%05d.bin", frameIndex)
            let fileURL = confidenceDirectory.appendingPathComponent(filename)
            do {
                try writeUInt8PixelBuffer(confidenceMap, to: fileURL)
                confidenceFile = relativePath(for: fileURL, relativeTo: artifacts.directoryURL)
            } catch {
                print("Failed to persist confidence map: \(error)")
            }
        }

        let entry = ARFrameLogEntry(
            frameIndex: frameIndex,
            timestamp: frame.timestamp,
            capturedAt: Date(),
            cameraTransform: cameraTransform,
            intrinsics: intrinsics,
            imageResolution: resolution,
            sceneDepthFile: sceneDepthFile,
            smoothedSceneDepthFile: smoothedDepthFile,
            confidenceFile: confidenceFile
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

extension VideoCaptureManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        startARSessionIfAvailable()
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        stopMotionUpdates()
        stopExposureLogging()
        stopARSession()
        if let error {
            let nsError = error as NSError
            let avError = (error as? AVError) ?? AVError(_nsError: nsError)
            let friendlyMessage: String
            if avError.code == .recordingStopped || avError.code == .videoDeviceInUseByAnotherClient {
                shouldSkipARKitOnNextRecording = true
                currentARKitArtifacts = nil
                friendlyMessage = "Recording stopped because the camera was busy. AR capture will be disabled on the next attempt."
                print("⚠️ [Capture] Camera ownership conflict detected; AR startup will be skipped on the next recording.")
            } else {
                friendlyMessage = error.localizedDescription
            }
            print("❌ [Capture] Recording failed: \(error.localizedDescription)")
            latestUploadPayload = nil
            captureState = .error(friendlyMessage)
        } else {
            let durationSeconds: Double?
            if output.recordedDuration.isNumeric {
                durationSeconds = CMTimeGetSeconds(output.recordedDuration)
            } else {
                durationSeconds = nil
            }

            persistManifest(duration: durationSeconds, synchronous: true)

            guard let artifacts = currentArtifacts else {
                latestUploadPayload = nil
                captureState = .error("Capture artifacts were unavailable.")
                return
            }

            print("📦 [Capture] Packaging artifacts …")
            let artifactsToPackage = artifacts
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.packageArtifacts(artifactsToPackage)
                    DispatchQueue.main.async {
                        self.latestUploadPayload = artifactsToPackage.uploadPayload
                        self.captureState = .finished(artifactsToPackage)
                        print("✅ [Capture] Packaging complete → \(artifactsToPackage.packageURL.lastPathComponent)")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.latestUploadPayload = nil
                        self.captureState = .error(error.localizedDescription)
                        print("❌ [Capture] Packaging failed: \(error.localizedDescription)")
                    }
                }
            }
        }
        currentArtifacts = nil
        currentARKitArtifacts = nil
        currentCameraIntrinsics = nil
        currentExposureSettings = nil
        exposureSamples = []
        arDataQueue.async { [weak self] in
            self?.arFrameCount = 0
            self?.exportedMeshAnchors.removeAll()
        }
    }
}

extension VideoCaptureManager: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        arDataQueue.async { [weak self] in
            self?.writeARFrame(frame)
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        arDataQueue.async { [weak self] in
            self?.exportMeshAnchors(anchors)
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        arDataQueue.async { [weak self] in
            self?.exportMeshAnchors(anchors)
        }
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

private extension VideoCaptureManager {
    func persistManifest(duration: Double?, synchronous: Bool = false) {
        guard let artifacts = currentArtifacts else { return }
        let intrinsics = currentCameraIntrinsics ?? CaptureManifest.CameraIntrinsics(
            resolutionWidth: 0,
            resolutionHeight: 0,
            intrinsicMatrix: nil,
            fieldOfView: nil,
            lensAperture: nil,
            minimumFocusDistance: nil
        )
        let exposureSettings = currentExposureSettings ?? CaptureManifest.ExposureSettings(mode: "unknown", pointOfInterest: nil, whiteBalanceMode: "unknown")
        let samples = exposureSamples

        let encoder = manifestEncoder
        let writeBlock = {
            let manifest = CaptureManifest(
                videoFile: artifacts.videoURL.lastPathComponent,
                motionLogFile: artifacts.motionLogURL.lastPathComponent,
                manifestFile: artifacts.manifestURL.lastPathComponent,
                recordedAt: artifacts.startedAt,
                durationSeconds: duration,
                cameraIntrinsics: intrinsics,
                exposureSettings: exposureSettings,
                exposureSamples: samples,
                arKit: self.makeARKitManifest(for: artifacts)
            )
            do {
                let data = try encoder.encode(manifest)
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

    func packageArtifacts(_ artifacts: RecordingArtifacts) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: artifacts.packageURL.path) {
            try fileManager.removeItem(at: artifacts.packageURL)
        }

        #if canImport(ZIPFoundation)
        try fileManager.zipItem(
            at: artifacts.directoryURL,
            to: artifacts.packageURL,
            shouldKeepParent: true
        )
        #else
        throw CaptureError.archiveUnavailable
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
            let wallTime: Date
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
