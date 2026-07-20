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
    ///
    /// Security rules make `referralCodes/{code}` server-write-only, so this
    /// only writes the code to the user's own document; the
    /// `onUserProfileWritten` Cloud Function registers the O(1) lookup entry.
    func ensureReferralCode(userId: String) async throws -> String {
        let userRef = db.collection("users").document(userId)
        let snapshot = try await userRef.getDocument()

        if let existing = snapshot.data()?["referralCode"] as? String, !existing.isEmpty {
            return existing
        }

        let code = generateCode()
        try await userRef.setData([
            "referralCode": code,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        return code
    }

    /// Builds a shareable referral URL.
    func shareURL(for code: String) -> URL {
        URL(string: "https://tryblueprint.io/join?ref=\(code)")!
    }

    /// Pre-composed share message for the referral.
    func shareMessage(for code: String) -> String {
        "Join me on Blueprint Capture — help record real spaces for robot evaluation. Use my invite code: \(code)\n\(shareURL(for: code).absoluteString)"
    }

    // MARK: - Fetch Referrals

    func fetchReferrals(userId: String) async throws -> [Referral] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("referrals")
            .order(by: "referredAt", descending: true)
            .limit(to: 200)
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

    // MARK: - Referral Attribution

    /// Attributes a new user to the referrer who owns `rawCode`.
    ///
    /// Security rules only allow a client to write its OWN user document, so
    /// this records `referredBy` + `referredByCode` there and the
    /// `onUserProfileWritten` Cloud Function validates the code and creates
    /// the referral record in the referrer's subcollection server-side.
    /// Invalid attributions are cleared by the server, so nothing here can
    /// fabricate a commission.
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

        var payload: [String: Any] = [
            "referredBy": referrerId,
            "referredByCode": code,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        let trimmedName = newUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            payload["displayName"] = trimmedName
        }
        try await newUserRef.setData(payload, merge: true)
        return .attributed(referrerId: referrerId)
    }

    /// Looks up which user owns a given referral code via the server-maintained
    /// `referralCodes/{code}` lookup collection (any signed-in user may read it).
    func findUserByReferralCode(_ code: String) async throws -> String? {
        let lookupSnap = try await db.collection("referralCodes").document(code).getDocument()
        return lookupSnap.data()?["ownerId"] as? String
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
