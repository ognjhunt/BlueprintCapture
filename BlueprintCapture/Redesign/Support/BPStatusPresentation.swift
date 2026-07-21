import Foundation

// MARK: - BPStatusPresentation
//
// Single source of truth for how backend statuses render in the BP experience:
// chip label, signal color, and the plain-language explanation used by the status
// glossary. Presentation only — statuses come from the backend and are never
// invented client-side.

enum BPStatusPresentation {
    struct Entry: Equatable {
        let label: String
        let signal: BPSignal
        let explanation: String
    }

    // MARK: Capture lifecycle

    static func entry(for status: CaptureStatus) -> Entry {
        switch status {
        case .draft:
            return Entry(
                label: "Draft",
                signal: .neutral,
                explanation: "Recorded on this device but not submitted yet."
            )
        case .readyToSubmit:
            return Entry(
                label: "Ready to submit",
                signal: .neutral,
                explanation: "The bundle is complete and waiting to upload."
            )
        case .submitted:
            return Entry(
                label: "Submitted",
                signal: .info,
                explanation: "Uploaded and registered. Review is required before payout eligibility."
            )
        case .underReview:
            return Entry(
                label: "In review",
                signal: .info,
                explanation: "Reviewers are checking coverage, depth, and privacy boundaries."
            )
        case .processing:
            return Entry(
                label: "Processing",
                signal: .info,
                explanation: "The bundle is being prepared for review."
            )
        case .qc:
            return Entry(
                label: "Quality check",
                signal: .info,
                explanation: "Final quality gates are running on the capture."
            )
        case .approved:
            return Entry(
                label: "Accepted",
                signal: .proof,
                explanation: "The capture passed review. Payout eligibility is confirmed."
            )
        case .needsRecapture:
            return Entry(
                label: "Recapture",
                signal: .caution,
                explanation: "Specific areas need another pass. The task notes say exactly where."
            )
        case .needsFix:
            return Entry(
                label: "Needs fix",
                signal: .caution,
                explanation: "Something in the bundle needs correcting before review can finish."
            )
        case .rejected:
            return Entry(
                label: "Not accepted",
                signal: .blocker,
                explanation: "The capture didn't meet requirements and is not payout-eligible."
            )
        case .paid:
            return Entry(
                label: "Paid",
                signal: .proof,
                explanation: "The payout for this accepted capture has been sent."
            )
        }
    }

    /// Glossary order — lifecycle first, then exception states.
    static let glossaryOrder: [CaptureStatus] = [
        .submitted, .processing, .underReview, .qc, .approved, .paid,
        .needsRecapture, .needsFix, .rejected,
    ]

    // MARK: Payout ledger

    static func entry(for status: PayoutLedgerStatus) -> Entry {
        switch status {
        case .pending:
            return Entry(
                label: "Pending",
                signal: .neutral,
                explanation: "Scheduled but not yet sent to your bank."
            )
        case .inTransit:
            return Entry(
                label: "In transit",
                signal: .info,
                explanation: "Sent — your bank is processing the transfer."
            )
        case .paid:
            return Entry(
                label: "Paid",
                signal: .proof,
                explanation: "The transfer arrived."
            )
        case .failed:
            return Entry(
                label: "Failed",
                signal: .blocker,
                explanation: "The transfer didn't complete. Check your payout details."
            )
        }
    }

    // MARK: Local upload queue

    static func entry(for state: UploadQueueViewModel.UploadStatus.State) -> Entry {
        switch state {
        case .queued:
            return Entry(
                label: "Queued",
                signal: .neutral,
                explanation: "Waiting to upload from this device."
            )
        case .uploading(let progress):
            let percent = Int((progress * 100).rounded())
            return Entry(
                label: "Uploading \(percent)%",
                signal: .info,
                explanation: "The bundle is uploading now."
            )
        case .completed:
            return Entry(
                label: "Submitted",
                signal: .info,
                explanation: "Uploaded and registered for review."
            )
        case .failed:
            return Entry(
                label: "Upload failed",
                signal: .blocker,
                explanation: "The upload didn't finish. Retry from the queue."
            )
        }
    }
}
