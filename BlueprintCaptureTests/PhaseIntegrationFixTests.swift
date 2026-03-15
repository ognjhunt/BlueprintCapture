import Foundation
import FirebaseFirestore
import Testing
@testable import BlueprintCapture

struct PhaseIntegrationFixTests {

    @Test
    func referralCodeParsingSupportsURLsAndRawCodes() {
        let url = URL(string: "https://blueprintcapture.app/join?ref=abcd23")!

        #expect(ReferralService.referralCode(from: url) == "ABCD23")
        #expect(ReferralService.referralCode(from: "abcd23") == "ABCD23")
        #expect(ReferralService.referralCode(from: " https://blueprintcapture.app/join?ref=ABCD23 ") == "ABCD23")
        #expect(ReferralService.referralCode(from: "invalid-code") == nil)
    }

    @Test
    func pendingReferralStorePersistsAndClears() {
        let suiteName = "PhaseIntegrationFixTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        PendingReferralStore.persist("ABCD23", defaults: defaults)
        #expect(PendingReferralStore.current(defaults: defaults) == "ABCD23")
        #expect(PendingReferralStore.consume(defaults: defaults) == "ABCD23")
        #expect(PendingReferralStore.current(defaults: defaults).isEmpty)

        PendingReferralStore.persist("WXYZ89", defaults: defaults)
        PendingReferralStore.clear(defaults: defaults)
        #expect(PendingReferralStore.current(defaults: defaults).isEmpty)
    }

    @Test @MainActor
    func captureDetailDecodingDefaultsMissingArrays() throws {
        let captureId = UUID()
        let json = """
        {
          "id": "\(captureId.uuidString.lowercased())",
          "target_address": "123 Demo Ave",
          "captured_at": "2026-03-14T12:00:00Z",
          "status": "approved",
          "quality": {
            "coverage": 91,
            "steadiness": 87
          },
          "earnings": {
            "base_payout_cents": 4200,
            "device_multiplier": 4
          }
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let detail = try decoder.decode(CaptureDetailResponse.self, from: Data(json.utf8))

        #expect(detail.id == captureId)
        #expect(detail.timeline.isEmpty)
        #expect(detail.earnings?.bonuses.isEmpty == true)
        #expect(detail.quality?.coverage == 91)
        #expect(detail.hasRenderableDetail)
    }

    @Test
    func achievementFallbackSupportsNormalizedAndLegacyFields() {
        let normalized = Achievement.unlockedDates(from: [
            "achievementIds": ["first_capture", "ten_captures"]
        ])
        #expect(Set(normalized.keys) == ["first_capture", "ten_captures"])

        let legacyList = Achievement.unlockedDates(from: [
            "achievements": ["marathon"]
        ])
        #expect(Set(legacyList.keys) == ["marathon"])

        let legacyMap = Achievement.unlockedDates(from: [
            "achievements": [
                "perfect_quality": Timestamp(date: Date(timeIntervalSince1970: 1000))
            ]
        ])
        #expect(Set(legacyMap.keys) == ["perfect_quality"])
        #expect(legacyMap["perfect_quality"] == Date(timeIntervalSince1970: 1000))
    }
}
