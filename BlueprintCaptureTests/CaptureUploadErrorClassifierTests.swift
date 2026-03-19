import Foundation
import Testing
@testable import BlueprintCapture

struct CaptureUploadErrorClassifierTests {

    @Test
    func classifierMatchesAlreadyFinalizedMessageFromPayload() {
        let error = NSError(
            domain: "com.google.HTTPStatus",
            code: 400,
            userInfo: [
                "data": Data("Upload has already been finalized.".utf8)
            ]
        )

        #expect(CaptureUploadErrorClassifier.isAlreadyFinalized(error))
    }

    @Test
    func classifierMatchesUnderlyingErrorMessage() {
        let underlying = NSError(
            domain: "com.google.HTTPStatus",
            code: 400,
            userInfo: [NSLocalizedDescriptionKey: "Upload has already been finalized."]
        )
        let error = NSError(
            domain: "FIRStorageErrorDomain",
            code: -13000,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )

        #expect(CaptureUploadErrorClassifier.isAlreadyFinalized(error))
    }

    @Test
    func classifierIgnoresUnrelatedErrors() {
        let error = NSError(
            domain: "FIRStorageErrorDomain",
            code: -13010,
            userInfo: [NSLocalizedDescriptionKey: "User does not have permission to access this object."]
        )

        #expect(!CaptureUploadErrorClassifier.isAlreadyFinalized(error))
    }
}
