import Foundation
import SwiftUI
import Combine
import FirebaseAuth

@MainActor
final class ReferralViewModel: ObservableObject {
    @Published var referralCode: String = ""
    @Published var referrals: [Referral] = []
    @Published var stats: ReferralStats = .empty
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = ReferralService.shared

    var shareURL: URL {
        service.shareURL(for: referralCode)
    }

    var shareMessage: String {
        service.shareMessage(for: referralCode)
    }

    var hasReferrals: Bool {
        !referrals.isEmpty
    }

    func load() async {
        guard let uid = Auth.auth().currentUser?.uid,
              UserDeviceService.hasRegisteredAccount() else { return }

        isLoading = true
        errorMessage = nil

        do {
            referralCode = try await service.ensureReferralCode(userId: uid)

            async let referralsTask = service.fetchReferrals(userId: uid)
            async let statsTask = service.fetchStats(userId: uid)

            referrals = try await referralsTask
            stats = try await statsTask
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
