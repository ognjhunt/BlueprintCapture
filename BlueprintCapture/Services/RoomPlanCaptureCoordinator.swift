import Foundation

public struct RoomPlanCaptureArtifacts: Equatable {
    public let rootDirectoryURL: URL
    public let capturedRoomURL: URL
    public let capturedRoomDataURL: URL
    public let parametricUSDZURL: URL
    public let parametricArchiveURL: URL?
}

public enum RoomPlanCaptureCoordinatorError: Error {
    case unsupported
    case alreadyRunning
    case notRunning
    case outputPreparationFailed(String)
    case exportFailed(String)
}

#if canImport(RoomPlan)
import RoomPlan
#if canImport(ZIPFoundation)
import ZIPFoundation
#endif

final class RoomPlanCaptureCoordinator: NSObject {
    private let session: RoomCaptureSession
    private var configuration = RoomCaptureSession.Configuration()
    private var outputDirectory: URL?
    private var completionHandlers: [(Result<RoomPlanCaptureArtifacts, Error>) -> Void] = []
    private var isRunning = false
    private var shouldIgnoreNextResult = false
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    override init() {
        session = RoomCaptureSession()
        super.init()
        configuration.isCoachingEnabled = false
        session.delegate = self
    }

    static var isSupported: Bool { RoomCaptureSession.isSupported }

    func startCapture(in directory: URL) throws -> Bool {
        guard Self.isSupported else { return false }
        guard !isRunning else { return true }

        let outputDir = directory.appendingPathComponent("roomplan", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } catch {
            throw RoomPlanCaptureCoordinatorError.outputPreparationFailed(error.localizedDescription)
        }

        outputDirectory = outputDir
        shouldIgnoreNextResult = false
        session.run(configuration: configuration)
        isRunning = true
        return true
    }

    func stopCapture(completion: @escaping (Result<RoomPlanCaptureArtifacts, Error>) -> Void) {
        guard isRunning else {
            completion(.failure(RoomPlanCaptureCoordinatorError.notRunning))
            return
        }
        completionHandlers.append(completion)
        session.stop()
    }

    func cancelCapture() {
        guard isRunning else { return }
        shouldIgnoreNextResult = true
        completionHandlers.removeAll()
        outputDirectory = nil
        session.stop()
        isRunning = false
    }

    private func finish(with result: Result<RoomPlanCaptureArtifacts, Error>) {
        isRunning = false
        let handlers = completionHandlers
        completionHandlers.removeAll()
        outputDirectory = nil
        handlers.forEach { handler in handler(result) }
    }

    private func persistArtifacts(room: CapturedRoom, data: CapturedRoomData, directory: URL) throws -> RoomPlanCaptureArtifacts {
        let roomURL = directory.appendingPathComponent("roomplan-room.json")
        let dataURL = directory.appendingPathComponent("roomplan-data.json")
        let usdzURL = directory.appendingPathComponent("roomplan-parametric.usdz")
        let archiveURL = directory.appendingPathComponent("roomplan-parametric.zip")

        let roomData = try jsonEncoder.encode(room)
        try roomData.write(to: roomURL, options: .atomic)

        let rawData = try jsonEncoder.encode(data)
        try rawData.write(to: dataURL, options: .atomic)

        try room.export(to: usdzURL, exportOptions: .parametric)

        var archive: URL?
        #if canImport(ZIPFoundation)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.removeItem(at: archiveURL)
        }
        guard let zip = Archive(url: archiveURL, accessMode: .create) else {
            throw RoomPlanCaptureCoordinatorError.exportFailed("Unable to create RoomPlan archive.")
        }
        try zip.addEntry(with: usdzURL.lastPathComponent, fileURL: usdzURL)
        archive = archiveURL
        #endif

        return RoomPlanCaptureArtifacts(
            rootDirectoryURL: directory,
            capturedRoomURL: roomURL,
            capturedRoomDataURL: dataURL,
            parametricUSDZURL: usdzURL,
            parametricArchiveURL: archive
        )
    }
}

extension RoomPlanCaptureCoordinator: RoomCaptureSessionDelegate {
    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?) {
        if shouldIgnoreNextResult {
            shouldIgnoreNextResult = false
            return
        }

        if let error {
            finish(with: .failure(error))
            return
        }

        guard let directory = outputDirectory else {
            finish(with: .failure(RoomPlanCaptureCoordinatorError.outputPreparationFailed("Missing output directory.")))
            return
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let builder = RoomBuilder(options: [])
                let room = try await builder.capturedRoom(from: data)
                let artifacts = try self.persistArtifacts(room: room, data: data, directory: directory)
                await MainActor.run {
                    self.finish(with: .success(artifacts))
                }
            } catch {
                await MainActor.run {
                    self.finish(with: .failure(error))
                }
            }
        }
    }
}

#else

final class RoomPlanCaptureCoordinator {
    static var isSupported: Bool { false }

    func startCapture(in directory: URL) throws -> Bool { false }

    func stopCapture(completion: @escaping (Result<RoomPlanCaptureArtifacts, Error>) -> Void) {
        completion(.failure(RoomPlanCaptureCoordinatorError.unsupported))
    }

    func cancelCapture() {}
}

#endif
