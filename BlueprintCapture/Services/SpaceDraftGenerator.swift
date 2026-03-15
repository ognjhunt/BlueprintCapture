import Foundation
import FoundationModels

/// Generates context notes for space submission drafts using the on-device LLM.
/// All methods gracefully no-op when Apple Intelligence is unavailable.
@available(iOS 26.0, *)
@Generable
struct SpaceDraft {
    @Guide(description: "2–3 sentences explaining why this place is worth 3D-capturing for a real-estate/mapping platform. Focus on: commercial activity, foot traffic, spatial complexity, or proximity to a high-demand area. Be factual and neutral.")
    var contextNotes: String

    @Guide(.anyOf(["RETAIL", "COMMERCIAL", "INDUSTRIAL", "OFFICE", "HOSPITALITY", "PUBLIC", "MIXED_USE"]))
    var suggestedCategory: String
}

@available(iOS 26.0, *)
@Generable
struct JobFocusTip {
    @Guide(description: "One actionable sentence telling the capturer exactly what to prioritize for this specific job. Be specific to the location and requirements. Start with an action verb. E.g., 'Focus on entry routes and loading bay corridors — those are the highest-value zones for this capture type.'")
    var tip: String
}

@available(iOS 26.0, *)
@Generable
struct ProfileDigest {
    @Guide(description: "1–2 sentences of personalized insight for this contributor. Mention their tier and capture count naturally. Be encouraging but factual. E.g., 'At Silver tier with 24 captures, you're in the top 30% of active contributors. Keep targeting commercial zones — they have the highest approval rates.'")
    var digestText: String
}

@available(iOS 26.0, *)
@Generable
struct RecordingGuidance {
    @Guide(description: "One short, actionable tip for a capturer who is actively recording right now. Specific to the job requirements. Start with an action verb. No more than 15 words. E.g., 'Work entry-to-exit: sweep the core zone before closing the path at the secondary exit.'")
    var tip: String
}

@available(iOS 26.0, *)
@Generable
struct EarningsInsight {
    @Guide(description: "1–2 sentences of earnings insight based on the contributor's capture stats. Be specific and motivating. Reference their numbers. E.g., 'Your 18 approved captures put you on track for Gold tier. Commercial jobs have historically paid out 1.8x faster than residential for contributors at your level.'")
    var insight: String
}

@MainActor
final class SpaceDraftGenerator {

    static let shared = SpaceDraftGenerator()
    private init() {}

    // MARK: - Availability

    var isAvailable: Bool {
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        return false
    }

    // MARK: - Generate (single response)

    func generateDraft(placeName: String, address: String?) async -> (contextNotes: String, suggestedCategory: String)? {
        guard #available(iOS 26.0, *) else { return nil }
        guard case .available = SystemLanguageModel.default.availability else { return nil }

        let session = LanguageModelSession(
            instructions: "You help contributors submit spaces for 3D capture review. Be concise and factual. No marketing language."
        )
        let addressClause = address.map { " at \($0)" } ?? ""
        let prompt = "The user wants to submit \"\(placeName)\"\(addressClause) as a 3D capture opportunity. Generate context notes and suggest a category."

        do {
            let response = try await session.respond(to: prompt, generating: SpaceDraft.self)
            return (response.content.contextNotes, response.content.suggestedCategory)
        } catch {
            print("[SpaceDraftGenerator] ✗ \(error)")
            return nil
        }
    }

    // MARK: - Stream (token-by-token)

    func streamDraft(
        placeName: String,
        address: String?,
        onPartial: @escaping @Sendable (String) -> Void
    ) async -> (contextNotes: String, suggestedCategory: String)? {
        guard #available(iOS 26.0, *) else { return nil }
        guard case .available = SystemLanguageModel.default.availability else { return nil }

        let session = LanguageModelSession(
            instructions: "You help contributors submit spaces for 3D capture review. Be concise and factual. No marketing language."
        )
        let addressClause = address.map { " at \($0)" } ?? ""
        let prompt = "The user wants to submit \"\(placeName)\"\(addressClause) as a 3D capture opportunity. Generate context notes and suggest a category."

        do {
            let stream = session.streamResponse(to: prompt, generating: SpaceDraft.self)
            var lastNotes = ""
            var lastCategory = ""

            for try await partial in stream {
                let notes = partial.content.contextNotes ?? ""
                let category = partial.content.suggestedCategory ?? ""
                if !notes.isEmpty { lastNotes = notes; onPartial(notes) }
                if !category.isEmpty { lastCategory = category }
            }

            return lastNotes.isEmpty ? nil : (lastNotes, lastCategory)
        } catch {
            print("[SpaceDraftGenerator] ✗ Stream error: \(error)")
            return nil
        }
    }
}
