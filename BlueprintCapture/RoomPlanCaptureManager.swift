import Foundation
import SwiftUI

struct RoomPlanCaptureExport: Equatable {
    let directoryURL: URL
    let usdzURL: URL
    let jsonURL: URL
    let archiveURL: URL?
}

enum RoomPlanCaptureError: LocalizedError {
    case unsupported
    case processingFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "RoomPlan capture isn't supported on this device."
        case .processingFailed(let message):
            return message
        case .exportFailed(let message):
            return message
        }
    }
}

protocol RoomPlanCaptureManaging: AnyObject {
    var isSupported: Bool { get }
    func makeCaptureView() -> UIView?
    func startCapture()
    func stopAndExport(to directory: URL, completion: @escaping (Result<RoomPlanCaptureExport, Error>) -> Void)
    func cancelCapture()
}

enum RoomPlanCaptureManagerFactory {
    static func makeManager() -> RoomPlanCaptureManaging {
#if canImport(RoomPlan)
        if #available(iOS 16.0, *) {
            return RoomPlanCaptureManager()
        } else {
            return RoomPlanCaptureUnavailableManager()
        }
#else
        return RoomPlanCaptureUnavailableManager()
#endif
    }
}

final class RoomPlanCaptureUnavailableManager: NSObject, RoomPlanCaptureManaging {
    var isSupported: Bool { false }
    func makeCaptureView() -> UIView? { nil }
    func startCapture() {}
    func stopAndExport(to directory: URL, completion: @escaping (Result<RoomPlanCaptureExport, Error>) -> Void) {
        completion(.failure(RoomPlanCaptureError.unsupported))
    }
    func cancelCapture() {}
}

#if canImport(RoomPlan)
import RoomPlan
#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

@available(iOS 16.0, *)
final class RoomPlanCaptureManager: NSObject, ObservableObject, RoomPlanCaptureManaging {
    private var captureView: RoomCaptureView?
    private var finalResult: CapturedRoom?
    private var exportCompletion: ((Result<RoomPlanCaptureExport, Error>) -> Void)?
    private var exportDestination: URL?
    private var latestError: Error?
    private var isRunning = false
    private let exportQueue = DispatchQueue(label: "com.blueprint.roomplan.export", qos: .userInitiated)

    var isSupported: Bool {
        RoomCaptureSession.isSupported
    }

    func makeCaptureView() -> UIView? {
        ensureCaptureView()
    }

    func startCapture() {
        guard isSupported, let view = ensureCaptureView(), !isRunning else { return }

        finalResult = nil
        latestError = nil

        var configuration = RoomCaptureSession.Configuration()
        configuration.captureMode = .parametric
        configuration.isAutoScanEnabled = true

        view.captureSession.delegate = self
        view.delegate = self
        view.captureSession.run(configuration: configuration)
        isRunning = true
    }

    func stopAndExport(to directory: URL, completion: @escaping (Result<RoomPlanCaptureExport, Error>) -> Void) {
        guard isSupported else {
            completion(.failure(RoomPlanCaptureError.unsupported))
            return
        }

        exportDestination = directory
        exportCompletion = completion

        if isRunning {
            captureView?.captureSession.stop()
            isRunning = false
        }

        attemptExportIfReady()
    }

    func cancelCapture() {
        exportCompletion = nil
        exportDestination = nil
        finalResult = nil
        latestError = nil
        if isRunning {
            captureView?.captureSession.stop()
        }
        isRunning = false
    }

    private func ensureCaptureView() -> RoomCaptureView? {
        if let view = captureView {
            return view
        }
        guard isSupported else { return nil }
        let view = RoomCaptureView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.captureSession.delegate = self
        view.delegate = self
        captureView = view
        return view
    }

    private func attemptExportIfReady() {
        guard let completion = exportCompletion else { return }

        if let error = latestError {
            exportCompletion = nil
            exportDestination = nil
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            return
        }

        guard let destination = exportDestination, let room = finalResult else {
            return
        }

        exportCompletion = nil
        exportDestination = nil

        exportQueue.async { [weak self] in
            guard let self else { return }
            do {
                let export = try self.export(room: room, to: destination)
                DispatchQueue.main.async {
                    completion(.success(export))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private func export(room: CapturedRoom, to directory: URL) throws -> RoomPlanCaptureExport {
        let fileManager = FileManager.default
        let roomPlanDirectory = directory.appendingPathComponent("roomplan", isDirectory: true)
        if fileManager.fileExists(atPath: roomPlanDirectory.path) {
            try fileManager.removeItem(at: roomPlanDirectory)
        }
        try fileManager.createDirectory(at: roomPlanDirectory, withIntermediateDirectories: true)

        let jsonURL = roomPlanDirectory.appendingPathComponent("RoomPlanParametric.json")
        let usdzURL = roomPlanDirectory.appendingPathComponent("RoomPlanParametric.usdz")
        let archiveURL = directory.appendingPathComponent("roomplan-parametric.zip")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let jsonData = try encoder.encode(room)
        try jsonData.write(to: jsonURL, options: .atomic)

        try room.export(to: usdzURL, exportOptions: .parametric)

        var archive: URL?
#if canImport(ZIPFoundation)
        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }
        try fileManager.zipItem(at: roomPlanDirectory, to: archiveURL, shouldKeepParent: true)
        archive = archiveURL
#endif

        return RoomPlanCaptureExport(
            directoryURL: roomPlanDirectory,
            usdzURL: usdzURL,
            jsonURL: jsonURL,
            archiveURL: archive
        )
    }
}

@available(iOS 16.0, *)
extension RoomPlanCaptureManager: RoomCaptureViewDelegate, RoomCaptureSessionDelegate {
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        if let error {
            latestError = RoomPlanCaptureError.processingFailed(error.localizedDescription)
            attemptExportIfReady()
            return false
        }
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        if let error {
            latestError = RoomPlanCaptureError.processingFailed(error.localizedDescription)
        } else {
            finalResult = processedResult
        }
        attemptExportIfReady()
    }
}
#endif

struct RoomPlanOverlayView: UIViewRepresentable {
    let manager: RoomPlanCaptureManaging

    func makeUIView(context: Context) -> UIView {
        manager.makeCaptureView() ?? UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
