// Extracted from CaptureUploadService.swift (behavior-preserving decomposition).
import Foundation

enum CaptureUploadErrorClassifier {
    static func isAlreadyFinalized(_ error: Error) -> Bool {
        errorMessages(from: error).contains { message in
            let normalized = message.lowercased()
            return normalized.contains("already been finalized") || normalized.contains("already finalized")
        }
    }

    private static func errorMessages(from error: Error) -> [String] {
        let nsError = error as NSError
        var messages: [String] = [nsError.localizedDescription]

        if let failureReason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
            messages.append(failureReason)
        }
        if let recoverySuggestion = nsError.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String {
            messages.append(recoverySuggestion)
        }
        if let payload = nsError.userInfo["data"] as? Data,
           let body = String(data: payload, encoding: .utf8) {
            messages.append(body)
        }
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            messages.append(contentsOf: errorMessages(from: underlyingError))
        }

        return messages
    }
}
