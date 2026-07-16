import Foundation
import Combine
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

// MARK: - BPCaptureHistoryStore
//
// Real capture history for the redesign History/Earnings screens, read from
// the signed-in user's own `capture_submissions` documents (the same records
// the upload path writes). No sample data: when there are no captures the
// screens show an honest empty state, and review verdicts only appear when the
// backend has actually written them.

struct BPCaptureHistoryEntry: Identifiable, Hashable {
    let id: String
    var site: String
    var capturedAt: Date?
    var status: String
    var captureSource: String?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    var meta: String {
        var parts: [String] = []
        if let captureSource, !captureSource.isEmpty {
            parts.append(captureSource.replacingOccurrences(of: "_", with: " "))
        }
        if let capturedAt {
            parts.append(Self.dateFormatter.string(from: capturedAt))
        }
        return parts.joined(separator: " · ")
    }

    /// True once the backend review pipeline has produced a verdict.
    var isReviewed: Bool {
        ["approved", "paid", "rejected", "needs_fix"].contains(status)
    }

    var needsFix: Bool { status == "needs_fix" }

    var chip: BPChip {
        switch status {
        case "approved": return BPChip(label: "Approved", signal: .proof)
        case "paid": return BPChip(label: "Paid", signal: .proof)
        case "under_review": return BPChip(label: "In review", signal: .info)
        case "needs_fix": return BPChip(label: "Needs fix", signal: .caution)
        case "rejected": return BPChip(label: "Rejected", signal: .blocker)
        case "submitted": return BPChip(label: "Submitted", signal: .info)
        case "upload_failed": return BPChip(label: "Upload failed", signal: .blocker)
        case "raw_validation_failed", "local_preflight_failed":
            return BPChip(label: "Needs recapture", signal: .caution)
        default:
            return BPChip(label: status.replacingOccurrences(of: "_", with: " "), signal: .neutral)
        }
    }
}

@MainActor
final class BPCaptureHistoryStore: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded
        case unavailable(String)
    }

    @Published private(set) var entries: [BPCaptureHistoryEntry] = []
    @Published private(set) var state: State = .loading

    var reviewedCount: Int { entries.filter(\.isReviewed).count }
    var needsFixCount: Int { entries.filter(\.needsFix).count }

    func refresh() async {
        #if canImport(FirebaseFirestore) && canImport(FirebaseAuth)
        guard FirebaseApp.app() != nil, let user = Auth.auth().currentUser, !user.isAnonymous else {
            entries = []
            state = .unavailable("Sign in to see your capture history.")
            return
        }

        do {
            // Equality-only query so no composite index is required; sorted
            // client-side by capture time.
            let snapshot = try await Firestore.firestore()
                .collection("capture_submissions")
                .whereField("creator_id", isEqualTo: user.uid)
                .limit(to: 200)
                .getDocuments()

            entries = snapshot.documents
                .compactMap(Self.entry(from:))
                .sorted { ($0.capturedAt ?? .distantPast) > ($1.capturedAt ?? .distantPast) }
            state = .loaded
        } catch {
            entries = []
            state = .unavailable("Could not load capture history. Pull to retry.")
        }
        #else
        entries = []
        state = .unavailable("Capture history requires Firebase.")
        #endif
    }

    #if canImport(FirebaseFirestore)
    private static func entry(from document: QueryDocumentSnapshot) -> BPCaptureHistoryEntry? {
        let data = document.data()
        guard let status = data["status"] as? String else { return nil }

        let site: String
        if let address = data["target_address"] as? String, !address.isEmpty {
            site = address
        } else if let captureId = data["capture_id"] as? String, !captureId.isEmpty {
            site = "Capture \(String(captureId.prefix(8)))"
        } else {
            site = "Capture \(String(document.documentID.prefix(8)))"
        }

        let capturedAt = (data["submitted_at"] as? Timestamp)?.dateValue()
            ?? (data["created_at"] as? Timestamp)?.dateValue()

        return BPCaptureHistoryEntry(
            id: document.documentID,
            site: site,
            capturedAt: capturedAt,
            status: status,
            captureSource: data["capture_source"] as? String
        )
    }
    #endif
}
