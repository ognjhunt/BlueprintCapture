import Foundation
import FirebaseFirestore

struct Achievement: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let unlockedAt: Date?

    var isUnlocked: Bool { unlockedAt != nil }

    /// All defined achievements in the system.
    static let all: [Achievement] = [
        Achievement(id: "first_capture", title: "First Capture", description: "Complete your first capture", icon: "camera.fill", unlockedAt: nil),
        Achievement(id: "ten_captures", title: "10 Captures", description: "Complete 10 captures", icon: "10.circle.fill", unlockedAt: nil),
        Achievement(id: "fifty_captures", title: "50 Captures", description: "Complete 50 captures", icon: "50.circle.fill", unlockedAt: nil),
        Achievement(id: "first_hundred", title: "First $100", description: "Earn $100 total", icon: "dollarsign.circle.fill", unlockedAt: nil),
        Achievement(id: "lidar_pro", title: "LiDAR Pro", description: "Complete 5 captures with LiDAR", icon: "sensor.tag.radiowaves.forward.fill", unlockedAt: nil),
        Achievement(id: "perfect_quality", title: "Perfect Quality", description: "Get a 100% quality score", icon: "star.fill", unlockedAt: nil),
        Achievement(id: "steady_hands", title: "Steady Hands", description: "Maintain 'Steady' for an entire capture", icon: "hand.raised.fill", unlockedAt: nil),
        Achievement(id: "referral_first", title: "First Referral", description: "Refer your first friend", icon: "person.2.fill", unlockedAt: nil),
        Achievement(id: "five_locations", title: "Explorer", description: "Capture 5 different location types", icon: "map.fill", unlockedAt: nil),
        Achievement(id: "marathon", title: "Marathon", description: "Complete a 30+ minute capture", icon: "clock.fill", unlockedAt: nil),
    ]

    /// Merge defined achievements with user's unlocked achievement IDs.
    static func merge(unlockedIds: [String: Date]) -> [Achievement] {
        all.map { achievement in
            Achievement(
                id: achievement.id,
                title: achievement.title,
                description: achievement.description,
                icon: achievement.icon,
                unlockedAt: unlockedIds[achievement.id]
            )
        }
    }

    static func unlockedDates(from userData: [String: Any]) -> [String: Date] {
        if let unlockedIds = userData["achievementIds"] as? [String] {
            return Dictionary(uniqueKeysWithValues: unlockedIds.map { ($0, Date()) })
        }
        if let unlockedMap = userData["achievements"] as? [String: Timestamp] {
            return unlockedMap.mapValues { $0.dateValue() }
        }
        if let unlockedList = userData["achievements"] as? [String] {
            return Dictionary(uniqueKeysWithValues: unlockedList.map { ($0, Date()) })
        }
        return [:]
    }
}
