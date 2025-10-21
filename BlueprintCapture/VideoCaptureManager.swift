import AVFoundation
import Combine
import CoreMotion

final class VideoCaptureManager: NSObject, ObservableObject {
    enum CaptureState {
        case idle
        case recording(URL)
        case finished(URL)
        case error(String)
    }

    @Published private(set) var captureState: CaptureState = .idle
    let session = AVCaptureSession()

    private let movieOutput = AVCaptureMovieFileOutput()
    private let motionManager = CMMotionManager()

    func configureSession() {
        guard session.inputs.isEmpty else { return }

        session.beginConfiguration()
        session.sessionPreset = .high

        do {
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                throw CaptureError.missingCamera
            }
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
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
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("walkthrough-\(UUID().uuidString).mov")
        movieOutput.startRecording(to: fileURL, recordingDelegate: self)
        captureState = .recording(fileURL)
        startMotionUpdates()
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
        stopMotionUpdates()
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates()
    }

    private func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
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
        if let error {
            captureState = .error(error.localizedDescription)
        } else {
            captureState = .finished(outputFileURL)
        }
    }
}
