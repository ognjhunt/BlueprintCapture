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
