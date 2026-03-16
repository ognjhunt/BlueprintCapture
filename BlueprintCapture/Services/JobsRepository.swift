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
            // Permission denied (unauthenticated/guest) — return placeholder cards so
            // the feed stays useful rather than showing a blank error state.
            let ns = error as NSError
            if ns.domain == "FIRFirestoreErrorDomain" && ns.code == 7 {
                return Self.mockJobs()
            }
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

    private func toURL(_ value: Any?) -> URL? {
        guard let string = value as? String, let url = URL(string: string) else { return nil }
        return url
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

        let permissionURL = toURL(data["permission_doc_url"])
        let thumbnailURL = toURL(data["thumbnail_url"]) ?? toURL(data["thumbnailURL"]) ?? toURL(data["image_url"])
        let heroImageURL = toURL(data["hero_image_url"]) ?? toURL(data["heroImageURL"])

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
            thumbnailURL: thumbnailURL,
            heroImageURL: heroImageURL,
            category: data["category"] as? String,
            instructions: toStringArray(data["instructions"]),
            allowedAreas: toStringArray(data["allowed_areas"]),
            restrictedAreas: toStringArray(data["restricted_areas"]),
            permissionDocURL: permissionURL,
            checkinRadiusM: toInt(data["checkin_radius_m"]) ?? 150,
            alertRadiusM: toInt(data["alert_radius_m"]) ?? 200,
            priority: toInt(data["priority"]) ?? 0,
            priorityWeight: toDouble(data["priority_weight"]) ?? 1.0,
            regionId: data["region_id"] as? String,
            jobType: ScanJob.JobType(rawValue: (data["task_type"] as? String) ?? "") ?? .curatedNearby,
            buyerRequestId: data["buyer_request_id"] as? String,
            siteSubmissionId: data["site_submission_id"] as? String,
            quotedPayoutCents: toInt(data["quoted_payout_cents"]),
            dueWindow: data["due_window"] as? String,
            approvalRequirements: toStringArray(data["approval_requirements"]),
            recaptureReason: data["recapture_reason"] as? String,
            rightsChecklist: toStringArray(data["rights_checklist"]),
            rightsProfile: data["rights_profile"] as? String,
            requestedOutputs: toStringArray(data["requested_outputs"]),
            workflowName: data["workflow_name"] as? String,
            workflowSteps: toStringArray(data["workflow_steps"]),
            targetKPI: data["target_kpi"] as? String,
            zone: data["zone"] as? String,
            shift: data["shift"] as? String,
            owner: data["owner"] as? String,
            facilityTemplate: data["facility_template"] as? String,
            benchmarkStations: toStringArray(data["benchmark_stations"]),
            lightingWindows: toStringArray(data["lighting_windows"]),
            movableObstacles: toStringArray(data["movable_obstacles"]),
            floorConditionNotes: toStringArray(data["floor_condition_notes"]),
            reflectiveSurfaceNotes: toStringArray(data["reflective_surface_notes"]),
            accessRules: toStringArray(data["access_rules"]),
            adjacentSystems: toStringArray(data["adjacent_systems"]),
            privacyRestrictions: toStringArray(data["privacy_restrictions"]),
            securityRestrictions: toStringArray(data["security_restrictions"]),
            knownBlockers: toStringArray(data["known_blockers"]),
            nonRoutineModes: toStringArray(data["non_routine_modes"]),
            peopleTrafficNotes: toStringArray(data["people_traffic_notes"]),
            captureRestrictions: toStringArray(data["capture_restrictions"])
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
                thumbnailURL: URL(string: "https://images.unsplash.com/photo-1586528116311-ad8dd3c8310d?auto=format&fit=crop&w=1200&q=80"),
                heroImageURL: URL(string: "https://images.unsplash.com/photo-1586528116311-ad8dd3c8310d?auto=format&fit=crop&w=1600&q=80"),
                category: "Warehouse",
                instructions: ["Walk all aisles", "Include entry/exit", "Avoid faces"],
                allowedAreas: ["Main floor"],
                restrictedAreas: ["Offices"],
                permissionDocURL: nil,
                checkinRadiusM: 150,
                alertRadiusM: 200,
                priority: 1,
                priorityWeight: 1.25,
                regionId: "bay-area",
                jobType: .buyerRequestedSpecialTask,
                buyerRequestId: "req_warehouse_001",
                siteSubmissionId: "req_warehouse_001",
                quotedPayoutCents: 4500,
                dueWindow: "managed",
                approvalRequirements: ["ops_review", "rights_review"],
                recaptureReason: nil,
                rightsChecklist: ["Permission doc", "Restricted zone list"],
                rightsProfile: "documented_permission",
                requestedOutputs: ["qualification", "preview_simulation"],
                workflowName: "Dock-to-staging tote handoff",
                workflowSteps: ["Dock entry", "Staging aisle", "Outbound handoff"],
                targetKPI: "handoff throughput",
                zone: "dock_a",
                shift: "day",
                owner: "warehouse_supervisor",
                facilityTemplate: "warehouse_dock_handoff",
                benchmarkStations: ["Dock threshold", "Staging aisle midpoint", "Outbound handoff mark"],
                lightingWindows: ["08:00-11:00 bright dock spill", "17:00-19:00 mixed interior lighting"],
                movableObstacles: ["Forklifts", "Empty pallets", "Loose staging totes"],
                floorConditionNotes: ["Painted dock threshold", "Smooth concrete with occasional dust"],
                reflectiveSurfaceNotes: ["Dock strip curtain", "Wrapped pallet faces"],
                accessRules: ["Escort required near loading door", "Do not block egress lane"],
                adjacentSystems: ["WMS", "dock_door_controls"],
                privacyRestrictions: ["No employee faces in shareable outputs"],
                securityRestrictions: ["Do not capture shipping labels at readable resolution"],
                knownBlockers: ["Forklift congestion during peaks"],
                nonRoutineModes: ["jam clearing"],
                peopleTrafficNotes: ["Shared aisle with forklifts and pickers"],
                captureRestrictions: ["Avoid office corridor"]
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
                thumbnailURL: URL(string: "https://images.unsplash.com/photo-1517142089942-ba376ce32a2e?auto=format&fit=crop&w=1200&q=80"),
                heroImageURL: nil,
                category: "Retail",
                instructions: ["Capture stock areas", "Include doorways"],
                allowedAreas: ["Backroom"],
                restrictedAreas: ["Registers", "Break room"],
                permissionDocURL: nil,
                checkinRadiusM: 150,
                alertRadiusM: 200,
                priority: 0,
                priorityWeight: 1.0,
                regionId: "bay-area",
                jobType: .curatedNearby,
                buyerRequestId: nil,
                siteSubmissionId: "job_mock_retail_002",
                quotedPayoutCents: 3000,
                dueWindow: "managed",
                approvalRequirements: ["ops_review"],
                recaptureReason: nil,
                rightsChecklist: ["Store manager approval"],
                rightsProfile: "policy_only",
                requestedOutputs: ["qualification"],
                workflowName: "Backroom replenishment walk",
                workflowSteps: ["Receiving shelf", "Stock corridor", "Sales-floor handoff door"],
                targetKPI: "replenishment cycle time",
                zone: "backroom_b",
                shift: "night",
                owner: "store_ops_manager",
                facilityTemplate: "retail_backroom_replenishment",
                benchmarkStations: ["Receiving shelf", "Stock corridor choke point", "Sales-floor handoff door"],
                lightingWindows: ["21:00-23:00 dim aisle lighting", "05:00-06:00 mixed stockroom lighting"],
                movableObstacles: ["Replenishment carts", "Ladder storage", "Flattened cardboard"],
                floorConditionNotes: ["Sealed concrete", "Occasional waxed patch near handoff door"],
                reflectiveSurfaceNotes: ["Metal stock shelving", "Plastic wrap bins"],
                accessRules: ["Store manager approval for stockroom", "No capture during cash close"],
                adjacentSystems: ["inventory_terminal"],
                privacyRestrictions: ["No employee faces in submitted clips"],
                securityRestrictions: ["Do not record cash handling zones"],
                knownBlockers: ["Narrow ladder storage alcove"],
                nonRoutineModes: ["closing cleanup"],
                peopleTrafficNotes: ["Variable clutter from replenishment carts"],
                captureRestrictions: ["Skip registers"]
            )
        ]
    }
}
