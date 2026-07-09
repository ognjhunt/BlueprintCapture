// Extracted from CaptureUploadService.swift (behavior-preserving decomposition).
import Foundation

struct CaptureUploadFilePlan: Equatable {
    static let completionMarkerFilename = "capture_upload_complete.json"

    let payloadFiles: [URL]
    let completionMarkerFile: URL?
    let totalPayloadBytes: Int64

    var uploadOrder: [URL] {
        payloadFiles + [completionMarkerFile].compactMap { $0 }
    }

    static func make(for uploadRoot: URL, fileManager: FileManager = .default) -> CaptureUploadFilePlan? {
        guard let enumerator = fileManager.enumerator(
            at: uploadRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var files: [URL] = []
        var totalBytes: Int64 = 0
        var completionMarkerFile: URL?
        for case let url as URL in enumerator {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                continue
            }
            if url.lastPathComponent == completionMarkerFilename {
                completionMarkerFile = url
            } else {
                files.append(url)
                if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    totalBytes += Int64(size)
                }
            }
        }
        files.sort { $0.path < $1.path }
        return CaptureUploadFilePlan(
            payloadFiles: files,
            completionMarkerFile: completionMarkerFile,
            totalPayloadBytes: totalBytes
        )
    }
}

struct CaptureUploadLimitDecision: Equatable {
    let allowed: Bool
    let reasons: [String]
    let totalPayloadBytes: Int64
    let maxFileSizeBytes: Int64
    let durationSeconds: Double?
    let maxDurationSeconds: Double
}

struct CaptureUploadLimitPolicy: Equatable {
    static let betaMaxFileSizeBytes: Int64 = 20 * 1024 * 1024 * 1024
    static let betaMaxDurationSeconds: Double = 45 * 60
    static let betaDefault = CaptureUploadLimitPolicy(
        maxFileSizeBytes: betaMaxFileSizeBytes,
        maxDurationSeconds: betaMaxDurationSeconds
    )

    let maxFileSizeBytes: Int64
    let maxDurationSeconds: Double

    func evaluate(plan: CaptureUploadFilePlan, durationSeconds: Double?) -> CaptureUploadLimitDecision {
        var reasons: [String] = []
        if plan.totalPayloadBytes > maxFileSizeBytes {
            reasons.append("capture_upload_size_exceeds_beta_limit")
        }
        if let durationSeconds,
           durationSeconds > maxDurationSeconds {
            reasons.append("capture_duration_exceeds_beta_limit")
        }
        return CaptureUploadLimitDecision(
            allowed: reasons.isEmpty,
            reasons: reasons,
            totalPayloadBytes: plan.totalPayloadBytes,
            maxFileSizeBytes: maxFileSizeBytes,
            durationSeconds: durationSeconds,
            maxDurationSeconds: maxDurationSeconds
        )
    }
}
