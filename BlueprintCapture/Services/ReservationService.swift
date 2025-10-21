import Foundation
import CoreLocation

protocol ReservationServiceProtocol: AnyObject {
    func reserve(target: Target, for duration: TimeInterval) async throws -> Reservation
    func cancelReservation(for targetId: String) async
    func reservationStatus(for targetId: String) -> ReservationStatus
}

struct Reservation: Equatable {
    let targetId: String
    let reservedUntil: Date
}

enum ReservationStatus: Equatable {
    case none
    case reserved(until: Date)
}

final class MockReservationService: ReservationServiceProtocol {
    private var storage: [String: Date] = [:]

    func reserve(target: Target, for duration: TimeInterval) async throws -> Reservation {
        let until = Date().addingTimeInterval(duration)
        storage[target.id] = until
        return Reservation(targetId: target.id, reservedUntil: until)
    }

    func cancelReservation(for targetId: String) async {
        storage.removeValue(forKey: targetId)
    }

    func reservationStatus(for targetId: String) -> ReservationStatus {
        if let until = storage[targetId], until > Date() {
            return .reserved(until: until)
        }
        storage.removeValue(forKey: targetId)
        return .none
    }
}


