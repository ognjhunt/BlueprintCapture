import SwiftUI

// MARK: - Presentation models
//
// Lightweight view models for the redesign. Screens render these; real data is
// bound in where a clean seam exists (auth/profile, capture launch). Imagery and
// sample assignment rows use the handoff's placeholder POV photos, as the spec
// allows — swap for real assignment photography when wired to the backend.

struct BPChip: Hashable {
    var label: String
    var signal: BPSignal
    var mono: Bool = false
    var showsDot: Bool = false
}

struct BPAssignment: Identifiable, Hashable {
    let id: String
    var site: String
    var imageName: String
    var payout: Double?
    var task: String
    var aisle: String
    var distance: String
    var status: BPChip
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

struct BPQAGate: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var sub: String
    var status: BPChip
}

struct BPPayout: Identifiable, Hashable {
    var id = UUID()
    var site: String
    var date: String
    var amount: Double
    var status: BPChip
}

struct BPHistoryItem: Identifiable, Hashable {
    var id = UUID()
    var site: String
    var imageName: String
    var meta: String
    var status: BPChip
}

struct BPNotification: Identifiable, Hashable {
    var id = UUID()
    var icon: String
    var signal: BPSignal
    var title: String
    var body: String
    var time: String
    var unread: Bool = true
}

struct BPMenuRow: Identifiable, Hashable {
    var id = UUID()
    var icon: String
    var title: String
    var trailing: String? = nil
    var trailingSignal: BPSignal? = nil
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

// MARK: - Sample data (handoff placeholders)

enum BPSample {
    static let capturerName = "Maya"
    static let capturerCity = "Sacramento, CA"

    static let activeAssignment = BPAssignment(
        id: "AS-7741",
        site: "Riverside Fulfillment Center",
        imageName: "pov-warehouse-tote",
        payout: nil,
        task: "Tote induction",
        aisle: "Aisle 7",
        distance: "0.4 mi",
        status: BPChip(label: "Review gated", signal: .info)
    )

    static let nearby: [BPAssignment] = [
        BPAssignment(id: "AS-7752", site: "Delta Cold Storage", imageName: "pov-cold-storage",
                     payout: 62.00, task: "Freezer aisle", aisle: "Zone B", distance: "1.2 mi",
                     status: BPChip(label: "Quoted assignment", signal: .proof)),
        BPAssignment(id: "AS-7760", site: "Northgate Retail Backroom", imageName: "pov-retail-backroom",
                     payout: nil, task: "Backroom sweep", aisle: "Dock 2", distance: "2.0 mi",
                     status: BPChip(label: "Rights pending", signal: .caution)),
        BPAssignment(id: "AS-7766", site: "Hartwell Loading Dock", imageName: "pov-loading-dock",
                     payout: nil, task: "Inbound staging", aisle: "Bay 4", distance: "2.6 mi",
                     status: BPChip(label: "Review gated", signal: .info)),
        BPAssignment(id: "AS-7771", site: "Meridian Packing Cell", imageName: "pov-packing-cell",
                     payout: nil, task: "Pack station", aisle: "Line 3", distance: "3.1 mi",
                     status: BPChip(label: "In review", signal: .info))
    ]

    static let captureTask = BPCaptureTask(
        id: "AS-7741",
        title: "Tote induction",
        site: "Riverside Fulfillment Center",
        imageName: "pov-warehouse-tote",
        meta: ["Tote induction", "Aisle 7", "0.4 mi"],
        requirements: [
            BPRequirement(title: "Capture path", detail: "Follow the suggested loop start to end.", signal: .proof),
            BPRequirement(title: "Depth", detail: "Keep LiDAR depth above 0.85 across the aisle.", signal: .proof),
            BPRequirement(title: "Restricted zones", detail: "Do not record the staff break area or screens.", signal: .caution),
            BPRequirement(title: "Privacy", detail: "Faces are blurred on-device before upload.", signal: .info)
        ],
        estPayout: nil
    )

    static let qaGates: [BPQAGate] = [
        BPQAGate(title: "Depth coverage", sub: "0.91 average across the loop", status: BPChip(label: "Pass", signal: .proof)),
        BPQAGate(title: "Poses / intrinsics", sub: "Pose lock held the full capture", status: BPChip(label: "Pass", signal: .proof)),
        BPQAGate(title: "Privacy", sub: "Faces blurred on-device", status: BPChip(label: "Pass", signal: .proof)),
        BPQAGate(title: "Coverage", sub: "Far end of the aisle under threshold", status: BPChip(label: "Review", signal: .caution))
    ]

    static let manifest: [(String, String)] = [
        ("capture_id", "CX-4821-A"),
        ("walkthrough", "WT-0093"),
        ("frames", "1,284"),
        ("meshes", "37")
    ]

    static let uploadManifest: [(String, String)] = [
        ("upload_id", "UP-2207"),
        ("chunks", "184 / 271"),
        ("checksum", "sha256:9f3c…b1"),
        ("eta", "00:42")
    ]

    static let history: [BPHistoryItem] = [
        BPHistoryItem(site: "Riverside Fulfillment Center", imageName: "pov-warehouse-tote", meta: "Tote induction · Jun 24", status: BPChip(label: "Validated", signal: .proof)),
        BPHistoryItem(site: "Meridian Packing Cell", imageName: "pov-packing-cell", meta: "Pack station · Jun 19", status: BPChip(label: "In review", signal: .info)),
        BPHistoryItem(site: "Northgate Retail Backroom", imageName: "pov-retail-backroom", meta: "Backroom sweep · Jun 17", status: BPChip(label: "Recapture", signal: .caution)),
        BPHistoryItem(site: "Delta Cold Storage", imageName: "pov-cold-storage", meta: "Freezer aisle · Jun 14", status: BPChip(label: "Validated", signal: .proof)),
        BPHistoryItem(site: "Inspection Bench Line", imageName: "pov-inspection-bench", meta: "QA bench · Jun 11", status: BPChip(label: "Validated", signal: .proof))
    ]

    static let notifications: [BPNotification] = [
        BPNotification(icon: "checkmark.seal", signal: .proof, title: "Capture validated", body: "Riverside Fulfillment Center passed QA. Payout status is handled separately.", time: "2h"),
        BPNotification(icon: "mappin.and.ellipse", signal: .info, title: "New assignment nearby", body: "Delta Cold Storage — freezer aisle, 1.2 mi away.", time: "5h"),
        BPNotification(icon: "arrow.counterclockwise", signal: .caution, title: "Recapture requested", body: "Northgate backroom — far corner coverage was low.", time: "1d"),
        BPNotification(icon: "creditcard", signal: .neutral, title: "Payout setup unavailable", body: "Cashout stays hidden until provider readiness is enabled for this cohort.", time: "2d", unread: false)
    ]

    static let principles: [BPPrinciple] = [
        BPPrinciple(index: 1, title: "Operator permission", body: "Only capture sites where the operator has granted access. Confirm permission before you record."),
        BPPrinciple(index: 2, title: "Privacy first", body: "Keep people, badges, screens, and restricted zones out of frame. Privacy review gates every capture before it is used."),
        BPPrinciple(index: 3, title: "Truthful evidence", body: "Capture what is really there. Don't stage, reshoot to mislead, or overclaim coverage.")
    ]
}
