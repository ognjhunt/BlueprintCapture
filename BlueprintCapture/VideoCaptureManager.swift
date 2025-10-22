import AVFoundation
import Combine
import CoreMotion
import CoreMedia

final class VideoCaptureManager: NSObject, ObservableObject {
    enum CaptureState {
        case idle
        case recording(RecordingArtifacts)
        case finished(RecordingArtifacts)
        case error(String)
    }

    struct RecordingArtifacts: Equatable {
        let baseFilename: String
        let videoURL: URL
        let motionLogURL: URL
        let manifestURL: URL
        let startedAt: Date

        var uploadPayload: CaptureUploadPayload {
            CaptureUploadPayload(videoURL: videoURL, motionLogURL: motionLogURL, manifestURL: manifestURL)
        }
    }

    struct CaptureUploadPayload: Codable, Equatable {
        let videoURL: URL
        let motionLogURL: URL
        let manifestURL: URL
    }

    @Published private(set) var captureState: CaptureState = .idle
    @Published private(set) var latestUploadPayload: CaptureUploadPayload?

    let session = AVCaptureSession()

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

    private var videoDevice: AVCaptureDevice?
    private var currentArtifacts: RecordingArtifacts?
    private var motionLogFileHandle: FileHandle?
    private var currentCameraIntrinsics: CaptureManifest.CameraIntrinsics?
    private var currentExposureSettings: CaptureManifest.ExposureSettings?
    private var exposureSamples: [CaptureManifest.ExposureSample] = []
    private var exposureTimer: Timer?

    func configureSession() {
        guard session.inputs.isEmpty else { return }

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
            captureState = .error(error.localizedDescription)
        }

        session.commitConfiguration()
    }

    func startSession() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }

    func stopSession() {
        guard session.isRunning else { return }
        session.stopRunning()
    }

    func startRecording() {
        guard !movieOutput.isRecording else { return }
        let baseName = "walkthrough-\(UUID().uuidString)"
        let tempDir = FileManager.default.temporaryDirectory
        let videoURL = tempDir.appendingPathComponent("\(baseName).mov")
        let motionURL = tempDir.appendingPathComponent("\(baseName)-motion.jsonl")
        let manifestURL = tempDir.appendingPathComponent("\(baseName)-manifest.json")
        let artifacts = RecordingArtifacts(
            baseFilename: baseName,
            videoURL: videoURL,
            motionLogURL: motionURL,
            manifestURL: manifestURL,
            startedAt: Date()
        )

        currentArtifacts = artifacts
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
        startMotionUpdates()
        startExposureLogging()

        movieOutput.startRecording(to: videoURL, recordingDelegate: self)
        captureState = .recording(artifacts)
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
        stopMotionUpdates()
        stopExposureLogging()
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

        var errorDescription: String? {
            switch self {
            case .missingCamera:
                return "Unable to access the back camera on this device."
            }
        }
    }
}

extension VideoCaptureManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        stopMotionUpdates()
        stopExposureLogging()
        if let error {
            latestUploadPayload = nil
            captureState = .error(error.localizedDescription)
        } else {
            let durationSeconds: Double?
            if output.recordedDuration.isNumeric {
                durationSeconds = CMTimeGetSeconds(output.recordedDuration)
            } else {
                durationSeconds = nil
            }

            persistManifest(duration: durationSeconds, synchronous: true)

            if let artifacts = currentArtifacts {
                latestUploadPayload = artifacts.uploadPayload
                captureState = .finished(artifacts)
            } else {
                captureState = .finished(
                    RecordingArtifacts(
                        baseFilename: outputFileURL.deletingPathExtension().lastPathComponent,
                        videoURL: outputFileURL,
                        motionLogURL: outputFileURL.deletingPathExtension().appendingPathExtension("motion.jsonl"),
                        manifestURL: outputFileURL.deletingPathExtension().appendingPathExtension("manifest.json"),
                        startedAt: Date()
                    )
                )
            }
        }
        currentArtifacts = nil
        currentCameraIntrinsics = nil
        currentExposureSettings = nil
        exposureSamples = []
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
                exposureSamples: samples
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
    }
}
