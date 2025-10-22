import Foundation
#if canImport(FirebaseFirestore)
import FirebaseFirestore
import FirebaseFirestoreSwift
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
        return reservation
    }

    func cancelReservation(for targetId: String) async {
        do {
            try await reservationsCollection.document(targetId).delete()
            cache.removeValue(forKey: targetId)
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
}
#endif
