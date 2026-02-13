import Foundation

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

protocol JobsRepositoryProtocol {
    func fetchActiveJobs(limit: Int) async throws -> [ScanJob]
}

enum JobsRepositoryError: LocalizedError {
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .decodingFailed:
            return "Unable to load scan jobs."
        }
    }
}

/// Firestore-backed implementation for curated scan jobs.
final class JobsRepository: JobsRepositoryProtocol {
    #if canImport(FirebaseFirestore)
    private let db: Firestore
    #endif
    private let collectionPath: String

    #if canImport(FirebaseFirestore)
    init(firestore: Firestore = Firestore.firestore(), collectionPath: String = "capture_jobs") {
        self.db = firestore
        self.collectionPath = collectionPath
    }
    #else
    init(collectionPath: String = "capture_jobs") {
        self.collectionPath = collectionPath
    }
    #endif

    func fetchActiveJobs(limit: Int = 200) async throws -> [ScanJob] {
        #if canImport(FirebaseFirestore)
        do {
            let snap = try await db
                .collection(collectionPath)
                .whereField("active", isEqualTo: true)
                .limit(to: max(1, min(limit, 200)))
                .getDocuments()
            return snap.documents.compactMap { decode(docId: $0.documentID, data: $0.data()) }
        } catch {
            throw error
        }
        #else
        // Preview/test fallback without Firebase
        return Self.mockJobs()
        #endif
    }

    // MARK: - Decoding

    #if canImport(FirebaseFirestore)
    private func toDate(_ value: Any?) -> Date? {
        if let ts = value as? Timestamp { return ts.dateValue() }
        if let d = value as? Date { return d }
        return nil
    }
    #endif

    private func toInt(_ value: Any?) -> Int? {
        if let v = value as? Int { return v }
        if let v = value as? Int64 { return Int(v) }
        if let v = value as? Double { return Int(v) }
        if let v = value as? NSNumber { return v.intValue }
        if let v = value as? String { return Int(v) }
        return nil
    }

    private func toDouble(_ value: Any?) -> Double? {
        if let v = value as? Double { return v }
        if let v = value as? NSNumber { return v.doubleValue }
        if let v = value as? String { return Double(v) }
        return nil
    }

    private func toStringArray(_ value: Any?) -> [String] {
        (value as? [String]) ?? []
    }

    private func decode(docId: String, data: [String: Any]) -> ScanJob? {
        guard
            let title = data["title"] as? String,
            let address = data["address"] as? String,
            let lat = toDouble(data["lat"]),
            let lng = toDouble(data["lng"]),
            let payoutCents = toInt(data["payout_cents"]),
            let estMinutes = toInt(data["est_minutes"])
        else {
            return nil
        }

        let active = (data["active"] as? Bool) ?? true

        let updatedAt: Date = {
            #if canImport(FirebaseFirestore)
            if let d = toDate(data["updated_at"]) { return d }
            #endif
            if let d = data["updated_at"] as? Date { return d }
            return Date()
        }()

        let permissionURL: URL? = {
            if let s = data["permission_doc_url"] as? String, let url = URL(string: s) { return url }
            return nil
        }()

        return ScanJob(
            id: docId,
            title: title,
            address: address,
            lat: lat,
            lng: lng,
            payoutCents: payoutCents,
            estMinutes: estMinutes,
            active: active,
            updatedAt: updatedAt,
            category: data["category"] as? String,
            instructions: toStringArray(data["instructions"]),
            allowedAreas: toStringArray(data["allowed_areas"]),
            restrictedAreas: toStringArray(data["restricted_areas"]),
            permissionDocURL: permissionURL,
            checkinRadiusM: toInt(data["checkin_radius_m"]) ?? 150,
            alertRadiusM: toInt(data["alert_radius_m"]) ?? 200,
            priority: toInt(data["priority"]) ?? 0
        )
    }

    // MARK: - Local fallback

    private static func mockJobs() -> [ScanJob] {
        let now = Date()
        return [
            ScanJob(
                id: "job_mock_warehouse_001",
                title: "Warehouse Dock A",
                address: "1 Warehouse Way, San Francisco, CA",
                lat: 37.7765,
                lng: -122.3940,
                payoutCents: 4500,
                estMinutes: 25,
                active: true,
                updatedAt: now,
                category: "Warehouse",
                instructions: ["Walk all aisles", "Include entry/exit", "Avoid faces"],
                allowedAreas: ["Main floor"],
                restrictedAreas: ["Offices"],
                permissionDocURL: nil,
                checkinRadiusM: 150,
                alertRadiusM: 200,
                priority: 1
            ),
            ScanJob(
                id: "job_mock_retail_002",
                title: "Retail Backroom B",
                address: "200 Market St, San Francisco, CA",
                lat: 37.7935,
                lng: -122.3966,
                payoutCents: 3000,
                estMinutes: 20,
                active: true,
                updatedAt: now,
                category: "Retail",
                instructions: ["Capture stock areas", "Include doorways"],
                allowedAreas: ["Backroom"],
                restrictedAreas: ["Registers", "Break room"],
                permissionDocURL: nil,
                checkinRadiusM: 150,
                alertRadiusM: 200,
                priority: 0
            )
        ]
    }
}

