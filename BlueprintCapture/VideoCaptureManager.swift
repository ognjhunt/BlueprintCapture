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
            let posesLogURL: URL
            let intrinsicsURL: URL
        }

        struct RoomPlanArtifacts: Equatable {
            let directoryURL: URL
            let usdzURL: URL
            let jsonURL: URL
            let archiveURL: URL?
        }

        let baseFilename: String
        let directoryURL: URL
        let videoURL: URL
        let motionLogURL: URL
        let manifestURL: URL
        let arKit: ARKitArtifacts?
        let packageURL: URL
        let startedAt: Date
        var roomPlan: RoomPlanArtifacts? = nil

        var shareItems: [Any] {
            var items: [Any] = [packageURL, videoURL, motionLogURL, manifestURL]
            if let arKit {
                items.append(arKit.frameLogURL)
            }
            if let roomPlan {
                if let archiveURL = roomPlan.archiveURL {
                    items.append(archiveURL)
                } else {
                    items.append(roomPlan.usdzURL)
                }
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
    private let roomPlanManager: RoomPlanCaptureManaging?
    private let roomPlanDispatchGroup = DispatchGroup()
    private var pendingRoomPlanError: Error?

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
    private var arPoseLogFileHandle: FileHandle?
    private var arIntrinsicsWritten: Bool = false
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
    private let screenRecorder = RPScreenRecorder.shared()
    private var screenRecordingWriter: ScreenRecordingWriter?
    private var usingScreenRecorder = false
    private var screenRecordingStartDate: Date?
    private var lastCaptureUsedScreenRecorder = false

    init(roomPlanManager: RoomPlanCaptureManaging? = nil) {
        self.roomPlanManager = roomPlanManager
        super.init()
        arSession.delegate = self
    }

    private var shouldUseScreenRecorder: Bool {
        if let manager = roomPlanManager {
            return manager.isSupported
        }
        return false
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
        guard !shouldUseScreenRecorder else {
            print("⚙️ [Capture] configureSession skipped — using screen recorder")
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
        guard !shouldUseScreenRecorder else { print("ℹ️ [Capture] startSession skipped — using screen recorder"); return }
        guard !session.isRunning else { print("ℹ️ [Capture] startSession ignored — already running"); return }
        DispatchQueue.global(qos: .userInitiated).async {
            print("🎥 [Capture] startRunning() …")
            self.session.startRunning()
            print("🎥 [Capture] session started (isRunning=\(self.session.isRunning))")
        }
    }

    func stopSession() {
        guard !shouldUseScreenRecorder else { print("ℹ️ [Capture] stopSession skipped — using screen recorder"); return }
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
        arFrameCount = 0
        exportedMeshAnchors.removeAll()
        latestUploadPayload = nil
        exposureSamples = []
        if shouldUseScreenRecorder {
            currentCameraIntrinsics = makeScreenIntrinsics()
            currentExposureSettings = nil
        } else {
            currentCameraIntrinsics = videoDevice.map(makeCameraIntrinsics)
            currentExposureSettings = videoDevice.map(makeExposureSettings)
        }
        persistManifest(duration: nil)

        prepareMotionLog(for: artifacts)
        guard motionLogFileHandle != nil else {
            currentArtifacts = nil
            return
        }
        prepareARKitLoggingIfNeeded(for: artifacts)
        startMotionUpdates()
        startExposureLogging()
        shouldSkipARKitOnNextRecording = false
        lastCaptureUsedScreenRecorder = shouldUseScreenRecorder

        if shouldUseScreenRecorder {
            startScreenRecording(for: artifacts)
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
        } else {
            guard movieOutput.isRecording else { print("ℹ️ [Capture] stopRecording ignored — not recording"); return }
        }
        print("⏹️ [Capture] stopRecording begin")
        if let roomPlanManager, let artifacts = currentArtifacts, roomPlanManager.isSupported {
            pendingRoomPlanError = nil
            roomPlanDispatchGroup.enter()
            print("🏠 [RoomPlan] Stopping RoomPlan capture for export")
            roomPlanManager.stopAndExport(to: artifacts.directoryURL) { [weak self] result in
                guard let self else { return }
                DispatchQueue.main.async {
                    defer { self.roomPlanDispatchGroup.leave() }
                    switch result {
                    case .success(let export):
                        print("✅ [RoomPlan] Exported parametric capture → \(export.usdzURL.lastPathComponent)")
                        if var updatedArtifacts = self.currentArtifacts {
                            updatedArtifacts.roomPlan = RecordingArtifacts.RoomPlanArtifacts(
                                directoryURL: export.directoryURL,
                                usdzURL: export.usdzURL,
                                jsonURL: export.jsonURL,
                                archiveURL: export.archiveURL
                            )
                            self.currentArtifacts = updatedArtifacts
                        }
                    case .failure(let error):
                        self.pendingRoomPlanError = error
                        print("⚠️ [RoomPlan] Export failed: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            pendingRoomPlanError = nil
        }
        if shouldUseScreenRecorder {
            stopScreenRecording()
        } else {
            movieOutput.stopRecording()
        }
        print("⏹️ [Capture] stopRecording requested")
    }

    private func startScreenRecording(for artifacts: RecordingArtifacts) {
        guard screenRecorder.isAvailable else {
            let message = "Screen recording is not available on this device."
            print("❌ [Capture] \(message)")
            DispatchQueue.main.async {
                self.latestUploadPayload = nil
                self.captureState = .error(message)
                self.cleanupAfterRecording()
            }
            return
        }

        let orientation = currentInterfaceOrientation()
        let outputSize = screenRecordingOutputSize(for: orientation)
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
        screenRecorder.stopCapture { [weak self] error in
            guard let self else { return }
            let writer = self.screenRecordingWriter
            self.screenRecordingWriter = nil
            let duration = self.screenRecordingStartDate.map { stopDate.timeIntervalSince($0) }
            self.screenRecordingStartDate = nil
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

    private func handleScreenRecorderFailure(_ error: Error) {
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
        stopMotionUpdates()
        stopExposureLogging()
        stopARSession()
        usingScreenRecorder = false

        DispatchQueue.main.async {
            if let error {
                let nsError = error as NSError
                var friendlyMessage = nsError.localizedDescription
                if let avError = (error as? AVError) ?? AVError(_nsError: nsError), avError.code == .deviceAlreadyUsedByAnotherSession {
                    self.shouldSkipARKitOnNextRecording = true
                    self.currentARKitArtifacts = nil
                    friendlyMessage = "Recording stopped because the camera was busy. AR capture will be disabled on the next attempt."
                    print("⚠️ [Capture] Camera ownership conflict detected; AR startup will be skipped on the next recording.")
                } else if nsError.domain == RPScreenRecorderErrorDomain {
                    friendlyMessage = "Screen recording failed: \(nsError.localizedDescription)"
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
                self.roomPlanDispatchGroup.wait()
                var artifactsToPackage: RecordingArtifacts?
                DispatchQueue.main.sync {
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
        #if canImport(ZIPFoundation)
        let packageURL = recordingDir.deletingLastPathComponent().appendingPathComponent("\(baseName).zip")
        #else
        // Fallback: use the directory itself as the upload package when ZIP is unavailable
        let packageURL = recordingDir
        #endif
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

        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: depth, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: confidence, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: mesh, withIntermediateDirectories: true)
            fileManager.createFile(atPath: frameLog.path, contents: nil)
            fileManager.createFile(atPath: posesLog.path, contents: nil)
            fileManager.createFile(atPath: intrinsics.path, contents: nil)
            return RecordingArtifacts.ARKitArtifacts(
                rootDirectoryURL: root,
                frameLogURL: frameLog,
                depthDirectoryURL: depth,
                confidenceDirectoryURL: confidence,
                meshDirectoryURL: mesh,
                posesLogURL: posesLog,
                intrinsicsURL: intrinsics
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
            arIntrinsicsWritten = false
        } catch {
            print("Failed to open ARKit frame log: \(error)")
            arFrameLogFileHandle = nil
            arPoseLogFileHandle = nil
            arIntrinsicsWritten = false
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
            arIntrinsicsWritten = false
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
        let frameId = String(format: "%06d", frameIndex + 1)
        let cameraTransform = matrixToArray(frame.camera.transform)
        let intrinsics = matrixToArray(frame.camera.intrinsics)
        let resolution = [Int(frame.camera.imageResolution.width), Int(frame.camera.imageResolution.height)]

        var sceneDepthFile: String?
        var smoothedDepthFile: String?
        var confidenceFile: String?

        if let depth = frame.sceneDepth, let depthDirectory = arKit.depthDirectoryURL {
            let filename = "\(frameId).png"
            let fileURL = depthDirectory.appendingPathComponent(filename)
            do {
                try writeDepthPNG(depth.depthMap, to: fileURL)
                sceneDepthFile = relativePath(for: fileURL, relativeTo: artifacts.directoryURL)
            } catch {
                print("Failed to persist scene depth map: \(error)")
            }
        }

        if let smoothedDepth = frame.smoothedSceneDepth, let depthDirectory = arKit.depthDirectoryURL {
            let filename = "smoothed-\(frameId).png"
            let fileURL = depthDirectory.appendingPathComponent(filename)
            do {
                try writeDepthPNG(smoothedDepth.depthMap, to: fileURL)
                smoothedDepthFile = relativePath(for: fileURL, relativeTo: artifacts.directoryURL)
            } catch {
                print("Failed to persist smoothed depth map: \(error)")
            }
        }

        if let confidenceMap = frame.smoothedSceneDepth?.confidenceMap ?? frame.sceneDepth?.confidenceMap,
           let confidenceDirectory = arKit.confidenceDirectoryURL {
            let filename = "\(frameId).png"
            let fileURL = confidenceDirectory.appendingPathComponent(filename)
            do {
                try writeConfidencePNG(confidenceMap, to: fileURL)
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

        // Also append to poses.jsonl with required schema
        if let poseHandle = arPoseLogFileHandle {
            let tDeviceSec = frame.timestamp
            let m = frame.camera.transform
            let T: [[Double]] = [
                [Double(m.columns.0.x), Double(m.columns.0.y), Double(m.columns.0.z), Double(m.columns.0.w)],
                [Double(m.columns.1.x), Double(m.columns.1.y), Double(m.columns.1.z), Double(m.columns.1.w)],
                [Double(m.columns.2.x), Double(m.columns.2.y), Double(m.columns.2.z), Double(m.columns.2.w)],
                [Double(m.columns.3.x), Double(m.columns.3.y), Double(m.columns.3.z), Double(m.columns.3.w)]
            ]
            struct PoseRow: Codable { let t_device_sec: Double; let frame_id: String; let T_world_camera: [[Double]] }
            let row = PoseRow(t_device_sec: tDeviceSec, frame_id: frameId, T_world_camera: T)
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
            let fx = Double(frame.camera.intrinsics.columns.0.x)
            let fy = Double(frame.camera.intrinsics.columns.1.y)
            let cx = Double(frame.camera.intrinsics.columns.2.x)
            let cy = Double(frame.camera.intrinsics.columns.2.y)
            let width = Int(frame.camera.imageResolution.width)
            let height = Int(frame.camera.imageResolution.height)
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
        let durationSeconds: Double?
        if output.recordedDuration.isNumeric {
            durationSeconds = CMTimeGetSeconds(output.recordedDuration)
        } else {
            durationSeconds = nil
        }
        handleRecordingCompletion(error: error, durationSeconds: durationSeconds)
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
    func cleanupAfterRecording() {
        currentArtifacts = nil
        currentARKitArtifacts = nil
        currentCameraIntrinsics = nil
        currentExposureSettings = nil
        exposureSamples = []
        pendingRoomPlanError = nil
        screenRecordingWriter = nil
        screenRecordingStartDate = nil
        usingScreenRecorder = false
        lastCaptureUsedScreenRecorder = false
        arDataQueue.async { [weak self] in
            self?.arFrameCount = 0
            self?.exportedMeshAnchors.removeAll()
        }
    }

    func persistManifest(duration: Double?, synchronous: Bool = false) {
        guard let artifacts = currentArtifacts else { return }
        let intr = currentCameraIntrinsics
        let width = intr?.resolutionWidth ?? 0
        let height = intr?.resolutionHeight ?? 0
        let fps: Int = {
            if lastCaptureUsedScreenRecorder {
                return UIScreen.main.maximumFramesPerSecond
            }
            if let d = videoDevice?.activeVideoMinFrameDuration, d.isNumeric { return Int(round(1.0 / d.seconds)) }
            return 30
        }()
        let deviceModel = UIDevice.current.model
        let osVersion = UIDevice.current.systemVersion
        let hasLiDAR = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        let epochMs = Int64(artifacts.startedAt.timeIntervalSince1970 * 1000.0)
        let writeBlock = {
            let dict: [String: Any] = [
                "scene_id": "",
                "video_uri": "",
                "device_model": deviceModel,
                "os_version": osVersion,
                "fps_source": fps,
                "width": width,
                "height": height,
                "capture_start_epoch_ms": epochMs,
                "has_lidar": hasLiDAR,
                "scale_hint_m_per_unit": hasLiDAR ? 1.0 : 1.0,
                "intended_space_type": "home"
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
