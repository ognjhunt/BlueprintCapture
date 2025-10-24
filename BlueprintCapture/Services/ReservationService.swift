import Foundation
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

protocol ReservationServiceProtocol: AnyObject {
    func reserve(target: Target, for duration: TimeInterval) async throws -> Reservation
    func cancelReservation(for targetId: String) async
    func reservationStatus(for targetId: String) -> ReservationStatus
    @discardableResult
    func observeReservation(for targetId: String, onChange: @escaping (ReservationStatus) -> Void) -> ReservationObservation
    func checkIn(targetId: String) async throws
    /// Returns the active reservation created by the current user if any exists and is not expired.
    func fetchActiveReservationForCurrentUser() async -> Reservation?
}

struct Reservation: Equatable {
    let targetId: String
    let reservedUntil: Date
}

enum ReservationStatus: Equatable {
    case none
    case reserved(until: Date)
}

final class ReservationObservation {
    private let cancellationHandler: () -> Void
    private var isCancelled = false

    init(_ cancellationHandler: @escaping () -> Void) {
        self.cancellationHandler = cancellationHandler
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        cancellationHandler()
    }

    deinit {
        cancel()
    }
}

#if canImport(FirebaseFirestore)
final class ReservationService: ReservationServiceProtocol {
    private let db: Firestore
    private let reservationsCollection: CollectionReference
    #if canImport(FirebaseAuth)
    private let auth: Auth
    #endif
    private var cache: [String: Reservation] = [:]
    private var listeners: [String: ListenerRegistration] = [:]

    init(firestore: Firestore = Firestore.firestore(),
         collectionPath: String = "reservations",
         auth: Auth = Auth.auth()) {
        self.db = firestore
        self.reservationsCollection = firestore.collection(collectionPath)
        #if canImport(FirebaseAuth)
        self.auth = auth
        #endif
    }

    deinit {
        listeners.values.forEach { $0.remove() }
    }

    func reserve(target: Target, for duration: TimeInterval) async throws -> Reservation {
        let now = Date()
        let newExpiration = now.addingTimeInterval(duration)
        // Enforce at most one active reservation per user by cancelling any previous active reservation
        if let existing = await fetchActiveReservationForCurrentUser(), existing.targetId != target.id {
            do {
                try await reservationsCollection.document(existing.targetId).delete()
                cache.removeValue(forKey: existing.targetId)
            } catch {
                // Non-fatal: continue to create the new reservation
            }
        }
        var data: [String: Any] = [
            "targetId": target.id,
            "reservedUntil": Timestamp(date: newExpiration),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        #if canImport(FirebaseAuth)
        if let uid = auth.currentUser?.uid {
            data["creatorId"] = uid
        }
        #endif
        do {
            try await reservationsCollection.document(target.id).setData(data, merge: true)
        } catch {
            throw error
        }
        let reservation = Reservation(targetId: target.id, reservedUntil: newExpiration)
        cache[target.id] = reservation
        // Mirror into target_state for global visibility
        let targetState = db.collection("target_state").document(target.id)
        var mirror: [String: Any] = [
            "status": "reserved",
            "reservedUntil": Timestamp(date: newExpiration),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        #if canImport(FirebaseAuth)
        if let uid = auth.currentUser?.uid { mirror["reservedBy"] = uid }
        #endif
        // Note: we don't have full Target here; caller also uses TargetStateService for mutations in the new path
        try? await targetState.setData(mirror, merge: true)
        return reservation
    }

    func cancelReservation(for targetId: String) async {
        do {
            try await reservationsCollection.document(targetId).delete()
            cache.removeValue(forKey: targetId)
            // Mirror cancellation
            let targetState = db.collection("target_state").document(targetId)
            try? await targetState.setData([
                "status": "available",
                "reservedBy": FieldValue.delete(),
                "reservedUntil": FieldValue.delete(),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            print("⚠️ Failed to cancel reservation for \(targetId): \(error)")
        }
    }

    func reservationStatus(for targetId: String) -> ReservationStatus {
        guard let reservation = cache[targetId], reservation.reservedUntil > Date() else {
            cache.removeValue(forKey: targetId)
            return .none
        }
        return .reserved(until: reservation.reservedUntil)
    }

    @discardableResult
    func observeReservation(for targetId: String, onChange: @escaping (ReservationStatus) -> Void) -> ReservationObservation {
        listeners[targetId]?.remove()
        let listener = reservationsCollection.document(targetId).addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            guard error == nil else {
                self.cache.removeValue(forKey: targetId)
                Task { @MainActor in onChange(.none) }
                return
            }
            guard
                let data = snapshot?.data(),
                let timestamp = data["reservedUntil"] as? Timestamp
            else {
                self.cache.removeValue(forKey: targetId)
                Task { @MainActor in onChange(.none) }
                return
            }
            let date = timestamp.dateValue()
            if date > Date() {
                let reservation = Reservation(targetId: targetId, reservedUntil: date)
                self.cache[targetId] = reservation
                Task { @MainActor in onChange(.reserved(until: date)) }
            } else {
                self.cache.removeValue(forKey: targetId)
                Task { @MainActor in onChange(.none) }
            }
        }
        listeners[targetId] = listener
        return ReservationObservation { [weak self] in
            listener.remove()
            self?.listeners.removeValue(forKey: targetId)
        }
    }

    func checkIn(targetId: String) async throws {
        var data: [String: Any] = [
            "checkedInAt": FieldValue.serverTimestamp(),
            "status": "in_progress"
        ]
        #if canImport(FirebaseAuth)
        if let uid = auth.currentUser?.uid {
            data["checkedInBy"] = uid
        }
        #endif
        try await reservationsCollection.document(targetId).setData(data, merge: true)
        // Mirror into target_state
        let targetState = db.collection("target_state").document(targetId)
        try? await targetState.setData([
            "status": "in_progress",
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func fetchActiveReservationForCurrentUser() async -> Reservation? {
        #if canImport(FirebaseAuth)
        guard let uid = auth.currentUser?.uid else { return nil }
        #else
        return nil
        #endif
        do {
            let nowTs = Timestamp(date: Date())
            var query: Query = reservationsCollection.whereField("creatorId", isEqualTo: uid)
            query = query.whereField("reservedUntil", isGreaterThan: nowTs)
            let snapshot = try await query.getDocuments()
            if let doc = snapshot.documents.first {
                let data = doc.data()
                if let targetId = data["targetId"] as? String, let ts = data["reservedUntil"] as? Timestamp {
                    let res = Reservation(targetId: targetId, reservedUntil: ts.dateValue())
                    cache[targetId] = res
                    return res
                }
            }
        } catch {
            // Swallow and treat as none
        }
        return nil
    }
}
#else
final class ReservationService: ReservationServiceProtocol {
    private var storage: [String: Date] = [:]
    private var observers: [String: (ReservationObservation, (ReservationStatus) -> Void)] = [:]

    func reserve(target: Target, for duration: TimeInterval) async throws -> Reservation {
        let until = Date().addingTimeInterval(duration)
        storage[target.id] = until
        notify(targetId: target.id, status: .reserved(until: until))
        return Reservation(targetId: target.id, reservedUntil: until)
    }

    func cancelReservation(for targetId: String) async {
        storage.removeValue(forKey: targetId)
        notify(targetId: targetId, status: .none)
    }

    func reservationStatus(for targetId: String) -> ReservationStatus {
        if let until = storage[targetId], until > Date() {
            return .reserved(until: until)
        }
        storage.removeValue(forKey: targetId)
        return .none
    }

    @discardableResult
    func observeReservation(for targetId: String, onChange: @escaping (ReservationStatus) -> Void) -> ReservationObservation {
        let token = ReservationObservation { [weak self] in
            self?.observers.removeValue(forKey: targetId)
        }
        observers[targetId] = (token, onChange)
        onChange(reservationStatus(for: targetId))
        return token
    }

    func checkIn(targetId: String) async throws { }

    private func notify(targetId: String, status: ReservationStatus) {
        if let handler = observers[targetId]?.1 {
            handler(status)
        }
    }

    func fetchActiveReservationForCurrentUser() async -> Reservation? {
        let now = Date()
        if let (targetId, until) = storage.first(where: { $0.value > now }) {
            return Reservation(targetId: targetId, reservedUntil: until)
        }
        return nil
    }
}
#endif
