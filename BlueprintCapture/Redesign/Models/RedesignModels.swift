import SwiftUI

// MARK: - Presentation models
//
// Lightweight view models for the redesign. Screens render REAL data only:
// identity binds from Firebase auth (RedesignCoordinator), the job feed comes
// from ScanHomeViewModel, and capture history comes from BPCaptureHistoryStore.
// The old BPSample dataset (fake personas, fake capture history, fake QA
// verdicts, fake notifications) was removed as a capture-truth violation —
// screens show honest empty states instead. Static, clearly-editorial copy
// (the rights principles) is the only remaining hardcoded content.

struct BPChip: Hashable {
    var label: String
    var signal: BPSignal
    var mono: Bool = false
    var showsDot: Bool = false
}

struct BPRequirement: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var detail: String
    var signal: BPSignal
}

struct BPCaptureTask: Identifiable, Hashable {
    let id: String
    var title: String
    var site: String
    var imageName: String
    var meta: [String]
    var requirements: [BPRequirement]
    var estPayout: Double?
}

struct BPPrinciple: Identifiable, Hashable {
    var id = UUID()
    var index: Int
    var title: String
    var body: String
}

// MARK: - Formatting

enum BPFormat {
    private static let money: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    static func currency(_ value: Double, fractionDigits: Int = 2) -> String {
        money.minimumFractionDigits = fractionDigits
        money.maximumFractionDigits = fractionDigits
        return money.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

// MARK: - Static editorial content

enum BPSample {
    /// Rights & privacy training copy — static editorial content, not data.
    static let principles: [BPPrinciple] = [
        BPPrinciple(index: 1, title: "Operator permission", body: "Only capture sites where the operator has granted access. Confirm permission before you record."),
        BPPrinciple(index: 2, title: "Privacy first", body: "Keep people, badges, screens, and restricted zones out of frame. Privacy review gates every capture before it is used."),
        BPPrinciple(index: 3, title: "Truthful evidence", body: "Capture what is really there. Don't stage, reshoot to mislead, or overclaim coverage.")
    ]
}
