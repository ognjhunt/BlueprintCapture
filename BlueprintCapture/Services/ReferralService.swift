import Foundation
import FirebaseAuth
import FirebaseFirestore

final class ReferralService {
    enum AttributionResult: Equatable {
        case attributed(referrerId: String)
        case invalidCode
        case alreadyAttributed
        case selfReferral
    }

    static let shared = ReferralService()

    private let db = Firestore.firestore()
    private let referralCodeLength = 6

    private init() {}

    // MARK: - Referral Code

    /// Generates a referral code if the user doesn't have one.
    /// Also writes to the `referralCodes/{code}` lookup collection for O(1) validation.
    func ensureReferralCode(userId: String) async throws -> String {
        let userRef = db.collection("users").document(userId)
        let snapshot = try await userRef.getDocument()

        if let existing = snapshot.data()?["referralCode"] as? String, !existing.isEmpty {
            // Backfill lookup entry if missing (handles existing users pre-migration)
            let lookupRef = db.collection("referralCodes").document(existing)
            let lookupSnap = try await lookupRef.getDocument()
            if !lookupSnap.exists {
                try await lookupRef.setData(["ownerId": userId])
            }
            return existing
        }

        let code = generateCode()
        let batch = db.batch()
        batch.setData([
            "referralCode": code,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: userRef, merge: true)
        batch.setData(["ownerId": userId], forDocument: db.collection("referralCodes").document(code))
        try await batch.commit()
        return code
    }

    /// Builds a shareable referral URL.
    func shareURL(for code: String) -> URL {
        URL(string: "https://blueprintcapture.app/join?ref=\(code)")!
    }

    /// Pre-composed share message for the referral.
    func shareMessage(for code: String) -> String {
        "Join me on Blueprint Capture and get paid to scan spaces! Use my code: \(code)\n\(shareURL(for: code).absoluteString)"
    }

    // MARK: - Fetch Referrals

    func fetchReferrals(userId: String) async throws -> [Referral] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("referrals")
            .order(by: "referredAt", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard
                let referredUserId = data["referredUserId"] as? String,
                let referredUserName = data["referredUserName"] as? String,
                let referredAt = (data["referredAt"] as? Timestamp)?.dateValue(),
                let statusRaw = data["status"] as? String,
                let status = ReferralStatus(rawValue: statusRaw)
            else { return nil }

            let earningsCents = data["lifetimeEarningsCents"] as? Int ?? 0

            return Referral(
                id: doc.documentID,
                referredUserId: referredUserId,
                referredUserName: referredUserName,
                referredAt: referredAt,
                status: status,
                lifetimeEarningsCents: earningsCents
            )
        }
    }

    func fetchStats(userId: String) async throws -> ReferralStats {
        let referrals = try await fetchReferrals(userId: userId)

        let signUps = referrals.filter { $0.status != .invited }.count
        let active = referrals.filter { $0.status == .active }.count
        let totalEarnings = referrals.reduce(0) { $0 + $1.lifetimeEarningsCents }

        return ReferralStats(
            invitesSent: referrals.count,
            signUps: signUps,
            activeCapturers: active,
            lifetimeEarningsCents: totalEarnings
        )
    }

    // MARK: - Create Referral Record

    /// Called when a new user signs up with a referral code. Creates a record in the referrer's subcollection.
    func createReferral(referrerId: String, referredUserId: String, referredUserName: String) async throws {
        let data: [String: Any] = [
            "referredUserId": referredUserId,
            "referredUserName": referredUserName,
            "referredAt": Timestamp(date: Date()),
            "status": ReferralStatus.signedUp.rawValue,
            "lifetimeEarningsCents": 0
        ]

        try await db.collection("users")
            .document(referrerId)
            .collection("referrals")
            .document(referredUserId)
            .setData(data)
    }

    func attributeReferral(
        code rawCode: String,
        newUserId: String,
        newUserName: String
    ) async throws -> AttributionResult {
        guard let code = Self.normalizedReferralCode(rawCode) else {
            return .invalidCode
        }

        let newUserRef = db.collection("users").document(newUserId)
        let newUserSnapshot = try await newUserRef.getDocument()
        if let referredBy = newUserSnapshot.data()?["referredBy"] as? String, !referredBy.isEmpty {
            return .alreadyAttributed
        }

        guard let referrerId = try await findUserByReferralCode(code) else {
            return .invalidCode
        }
        guard referrerId != newUserId else {
            return .selfReferral
        }

        let batch = db.batch()
        batch.setData([
            "referredBy": referrerId,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: newUserRef, merge: true)
        batch.setData([
            "referredUserId": newUserId,
            "referredUserName": newUserName,
            "referredAt": Timestamp(date: Date()),
            "status": ReferralStatus.signedUp.rawValue,
            "lifetimeEarningsCents": 0
        ], forDocument: db.collection("users")
            .document(referrerId)
            .collection("referrals")
            .document(newUserId), merge: true)
        try await batch.commit()
        return .attributed(referrerId: referrerId)
    }

    /// Looks up which user owns a given referral code.
    /// Uses the `referralCodes/{code}` lookup collection for O(1) direct reads.
    /// Falls back to a users query for codes created before the lookup collection was introduced.
    func findUserByReferralCode(_ code: String) async throws -> String? {
        let lookupSnap = try await db.collection("referralCodes").document(code).getDocument()
        if let ownerId = lookupSnap.data()?["ownerId"] as? String {
            return ownerId
        }

        // Fallback: query users collection (handles pre-migration codes)
        let snapshot = try await db.collection("users")
            .whereField("referralCode", isEqualTo: code)
            .limit(to: 1)
            .getDocuments()

        if let userId = snapshot.documents.first?.documentID {
            // Backfill the lookup entry so future lookups are fast
            try? await db.collection("referralCodes").document(code).setData(["ownerId": userId])
            return userId
        }

        return nil
    }

    // MARK: - Private

    private func generateCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // Exclude ambiguous chars
        return String((0..<referralCodeLength).map { _ in chars.randomElement()! })
    }

    static func referralCode(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawCode = components.queryItems?.first(where: { $0.name == "ref" })?.value else {
            return nil
        }
        return normalizedReferralCode(rawCode)
    }

    static func referralCode(from rawString: String?) -> String? {
        guard let rawString = rawString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawString.isEmpty else {
            return nil
        }
        if let url = URL(string: rawString), let code = referralCode(from: url) {
            return code
        }
        return normalizedReferralCode(rawString)
    }

    static func normalizedReferralCode(_ rawCode: String) -> String? {
        let code = rawCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        guard code.count == 6,
              code.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return code
    }
}
