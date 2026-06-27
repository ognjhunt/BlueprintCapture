import SwiftUI
import UIKit
import AVFoundation

// MARK: - BPCameraPreview
//
// Live back-camera preview behind the viewfinder overlay. Falls back to a dark
// instrument backdrop when no camera is available (simulator, denied permission),
// so the overlay always reads. Real depth/pose metrics come from the ARKit
// pipeline; this view is the optical feed only.

struct BPCameraPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.start()
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}

    static func dismantleUIView(_ uiView: CameraPreviewUIView, coordinator: ()) {
        uiView.stop()
    }
}

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    private var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "io.blueprint.viewfinder.session")
    private var configured = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(BP.viewfinder)
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func start() {
        #if targetEnvironment(simulator)
        return // no capture device on simulator
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.configureAndRun() }
            }
        default:
            break
        }
        #endif
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureAndRun() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .high
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                   let input = try? AVCaptureDeviceInput(device: device),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                self.session.commitConfiguration()
                self.configured = true
                DispatchQueue.main.async { self.previewLayer.session = self.session }
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }
}
