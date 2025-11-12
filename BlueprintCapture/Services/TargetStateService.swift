import Foundation
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(Geohasher)
import Geohasher
#endif

// Represents the live status of a target/location (by Google Place ID)
struct TargetState: Equatable {
    enum Status: String, Codable { case available, reserved, in_progress, completed }

    let status: Status
    let reservedBy: String?
    let reservedUntil: Date?
    let checkedInBy: String?
    let completedAt: Date?
    let lat: Double?
    let lng: Double?
    let geohash: String?
    let updatedAt: Date?
}

final class TargetStateObservation {
    private let cancellationHandler: () -> Void
    private var isCancelled = false

    init(_ cancellationHandler: @escaping () -> Void) { self.cancellationHandler = cancellationHandler }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        cancellationHandler()
    }

    deinit { cancel() }
}

protocol TargetStateServiceProtocol: AnyObject {
    func batchFetchStates(for targetIds: [String]) async -> [String: TargetState]
    @discardableResult
    func observeState(for targetId: String, onChange: @escaping (TargetState?) -> Void) -> TargetStateObservation

    // Mutations
    func reserve(target: Target, for duration: TimeInterval) async throws -> Reservation
    func cancelReservation(for targetId: String) async
    func checkIn(targetId: String) async throws
    func complete(targetId: String) async throws
    func fetchActiveReservationForCurrentUser() async -> Reservation?
}

#if canImport(FirebaseFirestore)
final class TargetStateService: TargetStateServiceProtocol {
    private let db: Firestore
    private let collection: CollectionReference
    #if canImport(FirebaseAuth)
    private let auth: Auth
    #endif
    private var listeners: [String: ListenerRegistration] = [:]

    init(firestore: Firestore = Firestore.firestore(), collectionPath: String = "target_state", auth: Auth = Auth.auth()) {
        self.db = firestore
        self.collection = firestore.collection(collectionPath)
        #if canImport(FirebaseAuth)
        self.auth = auth
        #endif
    }

    // MARK: - Helpers
    private func toState(_ data: [String: Any]) -> TargetState? {
        let statusStr = (data["status"] as? String) ?? TargetState.Status.available.rawValue
        guard let status = TargetState.Status(rawValue: statusStr) else { return nil }
        let reservedBy = data["reservedBy"] as? String
        let reservedUntil = (data["reservedUntil"] as? Timestamp)?.dateValue()
        let checkedInBy = data["checkedInBy"] as? String
        let completedAt = (data["completedAt"] as? Timestamp)?.dateValue()
        let lat = data["lat"] as? Double
        let lng = data["lng"] as? Double
        let geohash = data["geohash"] as? String
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        return TargetState(status: status, reservedBy: reservedBy, reservedUntil: reservedUntil, checkedInBy: checkedInBy, completedAt: completedAt, lat: lat, lng: lng, geohash: geohash, updatedAt: updatedAt)
    }

    func batchFetchStates(for targetIds: [String]) async -> [String: TargetState] {
        guard !targetIds.isEmpty else { return [:] }
        var map: [String: TargetState] = [:]
        let chunks: [[String]] = stride(from: 0, to: targetIds.count, by: 10).map { start in
            Array(targetIds[start..<min(start + 10, targetIds.count)])
        }
        for chunk in chunks {
            do {
                let query = collection.whereField(FieldPath.documentID(), in: chunk)
                let snapshot = try await query.getDocuments()
                for doc in snapshot.documents {
                    if let state = toState(doc.data()) { map[doc.documentID] = state }
                }
            } catch {
                // Skip chunk on error; partial data is acceptable
            }
        }
        return map
    }

    @discardableResult
    func observeState(for targetId: String, onChange: @escaping (TargetState?) -> Void) -> TargetStateObservation {
        listeners[targetId]?.remove()
        let listener = collection.document(targetId).addSnapshotListener { [weak self] snapshot, _ in
            guard let self = self else { return }
            if let data = snapshot?.data(), let state = self.toState(data) {
                Task { @MainActor in onChange(state) }
            } else {
                Task { @MainActor in onChange(nil) }
            }
        }
        listeners[targetId] = listener
        return TargetStateObservation { [weak self] in
            listener.remove()
            self?.listeners.removeValue(forKey: targetId)
        }
    }

    // MARK: - Mutations
    func reserve(target: Target, for duration: TimeInterval) async throws -> Reservation {
        let now = Date()
        let until = now.addingTimeInterval(duration)
        // Resolve a stable identifier for the current user/device (works even when not authenticated)
        #if canImport(FirebaseAuth)
        let userId = auth.currentUser?.uid ?? UserDeviceService.resolvedUserId()
        #else
        let userId = UserDeviceService.resolvedUserId()
        #endif
        let doc = collection.document(target.id)
        // Read-then-write with simple guards; acceptable for MVP
        do {
            let snapshot = try await doc.getDocument()
            if let data = snapshot.data(), let state = toState(data) {
                if state.status == .reserved, let exp = state.reservedUntil, exp > now, state.reservedBy != userId {
                    throw NSError(domain: "TargetStateService", code: 409, userInfo: [NSLocalizedDescriptionKey: "Already reserved"])
                }
                if state.status == .completed { throw NSError(domain: "TargetStateService", code: 410, userInfo: [NSLocalizedDescriptionKey: "Already completed"]) }
            }
        } catch { /* proceed on not found */ }

        var payload: [String: Any] = [
            "status": TargetState.Status.reserved.rawValue,
            "reservedUntil": Timestamp(date: until),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        payload["reservedBy"] = userId
        payload["lat"] = target.lat
        payload["lng"] = target.lng
        #if canImport(Geohasher)
        payload["geohash"] = Geohasher.encode(latitude: target.lat, longitude: target.lng, length: 7)
        #endif
        try await doc.setData(payload, merge: true)
        return Reservation(targetId: target.id, reservedUntil: until)
    }

    func cancelReservation(for targetId: String) async {
        let doc = collection.document(targetId)
        // Only allow cancel if the current user/device is the reserver
        #if canImport(FirebaseAuth)
        let userId = auth.currentUser?.uid ?? UserDeviceService.resolvedUserId()
        #else
        let userId = UserDeviceService.resolvedUserId()
        #endif
        do {
            let snapshot = try await doc.getDocument()
            let data = snapshot.data() ?? [:]
            let reservedBy = data["reservedBy"] as? String
            if reservedBy == nil || reservedBy == userId {
                try await doc.setData([
                    "status": TargetState.Status.available.rawValue,
                    "reservedBy": FieldValue.delete(),
                    "reservedUntil": FieldValue.delete(),
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
            } else {
                print("⚠️ Refusing to cancel reservation for \(targetId): owned by another user")
            }
        } catch {
            print("⚠️ Failed to cancel target_state for \(targetId): \(error)")
        }
    }

    func checkIn(targetId: String) async throws {
        #if canImport(FirebaseAuth)
        let userId = auth.currentUser?.uid ?? UserDeviceService.resolvedUserId()
        #else
        let userId = UserDeviceService.resolvedUserId()
        #endif
        let doc = collection.document(targetId)
        let snapshot = try await doc.getDocument()
        if let data = snapshot.data(), let state = toState(data) {
            let now = Date()
            if state.status == .reserved, (state.reservedBy == userId), (state.reservedUntil ?? now) > now {
                try await doc.setData([
                    "status": TargetState.Status.in_progress.rawValue,
                    "checkedInBy": userId,
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
                return
            }
        }
        throw NSError(domain: "TargetStateService", code: 403, userInfo: [NSLocalizedDescriptionKey: "Cannot check in"])
    }

    func complete(targetId: String) async throws {
        #if canImport(FirebaseAuth)
        let userId = auth.currentUser?.uid ?? UserDeviceService.resolvedUserId()
        #else
        let userId = UserDeviceService.resolvedUserId()
        #endif
        let doc = collection.document(targetId)
        let snapshot = try await doc.getDocument()
        if let data = snapshot.data(), let state = toState(data) {
            if state.status == .in_progress && (state.checkedInBy == userId) {
                print("✅ [TargetState] Completing target=\(targetId) for user=\(userId)")
                try await doc.setData([
                    "status": TargetState.Status.completed.rawValue,
                    "completedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
                return
            }
        }
        print("⚠️ [TargetState] Cannot complete target=\(targetId); state mismatch or ownership issue")
        throw NSError(domain: "TargetStateService", code: 403, userInfo: [NSLocalizedDescriptionKey: "Cannot complete"])
    }

    func fetchActiveReservationForCurrentUser() async -> Reservation? {
        #if canImport(FirebaseAuth)
        let uid = auth.currentUser?.uid ?? UserDeviceService.resolvedUserId()
        #else
        let uid = UserDeviceService.resolvedUserId()
        #endif
        do {
            let nowTs = Timestamp(date: Date())
            var q: Query = collection
                .whereField("status", isEqualTo: TargetState.Status.reserved.rawValue)
                .whereField("reservedBy", isEqualTo: uid)
            q = q.whereField("reservedUntil", isGreaterThan: nowTs)
            let snap = try await q.limit(to: 1).getDocuments()
            if let doc = snap.documents.first, let ts = (doc.data()["reservedUntil"] as? Timestamp)?.dateValue() {
                return Reservation(targetId: doc.documentID, reservedUntil: ts)
            }
        } catch { }
        return nil
    }
}
#else
// Mock implementation for preview/testing without Firebase
final class TargetStateService: TargetStateServiceProtocol {
    private var store: [String: TargetState] = [:]
    private var observers: [String: (TargetStateObservation, (TargetState?) -> Void)] = [:]

    func batchFetchStates(for targetIds: [String]) async -> [String : TargetState] {
        var map: [String: TargetState] = [:]
        for id in targetIds { if let s = store[id] { map[id] = s } }
        return map
    }

    @discardableResult
    func observeState(for targetId: String, onChange: @escaping (TargetState?) -> Void) -> TargetStateObservation {
        let token = TargetStateObservation { [weak self] in self?.observers.removeValue(forKey: targetId) }
        observers[targetId] = (token, onChange)
        onChange(store[targetId])
        return token
    }

    func reserve(target: Target, for duration: TimeInterval) async throws -> Reservation {
        let until = Date().addingTimeInterval(duration)
        store[target.id] = TargetState(status: .reserved, reservedBy: nil, reservedUntil: until, checkedInBy: nil, completedAt: nil, lat: target.lat, lng: target.lng, geohash: nil, updatedAt: Date())
        notify(id: target.id)
        return Reservation(targetId: target.id, reservedUntil: until)
    }

    func cancelReservation(for targetId: String) async {
        store[targetId] = TargetState(status: .available, reservedBy: nil, reservedUntil: nil, checkedInBy: nil, completedAt: nil, lat: nil, lng: nil, geohash: nil, updatedAt: Date())
        notify(id: targetId)
    }

    func checkIn(targetId: String) async throws {
        if var s = store[targetId] { s = TargetState(status: .in_progress, reservedBy: s.reservedBy, reservedUntil: s.reservedUntil, checkedInBy: s.reservedBy, completedAt: nil, lat: s.lat, lng: s.lng, geohash: s.geohash, updatedAt: Date()); store[targetId] = s; notify(id: targetId) }
    }

    func complete(targetId: String) async throws {
        if var s = store[targetId] { s = TargetState(status: .completed, reservedBy: s.reservedBy, reservedUntil: s.reservedUntil, checkedInBy: s.checkedInBy, completedAt: Date(), lat: s.lat, lng: s.lng, geohash: s.geohash, updatedAt: Date()); store[targetId] = s; notify(id: targetId) }
    }

    func fetchActiveReservationForCurrentUser() async -> Reservation? {
        let now = Date()
        for (id, s) in store {
            if s.status == .reserved, let until = s.reservedUntil, until > now { return Reservation(targetId: id, reservedUntil: until) }
        }
        return nil
    }

    private func notify(id: String) { if let handler = observers[id]?.1 { handler(store[id]) } }
}
#endif


