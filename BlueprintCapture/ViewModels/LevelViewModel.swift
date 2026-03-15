import Foundation
import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class LevelViewModel: ObservableObject {
    @Published var currentLevel: CapturerLevel = .novice
    @Published var captureCount: Int = 0
    @Published var avgQualityScore: Double = 0
    @Published var progressToNext: Double = 0
    @Published var achievements: [Achievement] = Achievement.all
    @Published var isLoading = false

    func load() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true

        do {
            let doc = try await Firestore.firestore().collection("users").document(uid).getDocument()
            let data = doc.data() ?? [:]

            captureCount = data["totalCaptureCount"] as? Int ?? data["numLocationsScanned"] as? Int ?? 0
            avgQualityScore = data["avgQualityScore"] as? Double ?? 0

            currentLevel = CapturerLevel.from(captureCount: captureCount, avgQuality: avgQualityScore)
            progressToNext = CapturerLevel.progressToNext(captureCount: captureCount, avgQuality: avgQualityScore)

            achievements = Achievement.merge(unlockedIds: Achievement.unlockedDates(from: data))
        } catch {
            print("⚠️ [Level] Failed to load: \(error.localizedDescription)")
        }

        isLoading = false
    }

    var unlockedCount: Int {
        achievements.filter(\.isUnlocked).count
    }

    var totalCount: Int {
        achievements.count
    }
}
