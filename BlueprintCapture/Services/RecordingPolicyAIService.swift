import Foundation

/// AI-powered recording policy verification service
/// Uses web search to verify recording policies for ambiguous venues
/// Supports Gemini with Google Search grounding (primary) and Perplexity API (alternative)
final class RecordingPolicyAIService {

    static let shared = RecordingPolicyAIService()

    private let session: URLSession
    private let geminiKeyProvider: () -> String?
    private let perplexityKeyProvider: () -> String?

    /// Cache for AI verification results
    private var cache: [String: AIVerificationResult] = [:]
    private let cacheQueue = DispatchQueue(label: "RecordingPolicyAIService.cache")

    init(
        session: URLSession = .shared,
        geminiKeyProvider: @escaping () -> String? = { AppConfig.geminiAPIKey() },
        perplexityKeyProvider: @escaping () -> String? = { AppConfig.perplexityAPIKey() }
    ) {
        self.session = session
        self.geminiKeyProvider = geminiKeyProvider
        self.perplexityKeyProvider = perplexityKeyProvider
    }

    // MARK: - Types

    struct AIVerificationResult: Codable {
        let hasRestrictions: Bool
        let confidence: Double          // 0.0 - 1.0
        let summary: String             // Brief explanation
        let sources: [String]?          // Source URLs if available
        let timestamp: Date

        var isStale: Bool {
            // Cache results for 7 days
            Date().timeIntervalSince(timestamp) > 7 * 24 * 60 * 60
        }
    }

    enum VerificationError: Error {
        case noAPIKeyAvailable
        case requestFailed(String)
        case parseFailed
        case rateLimited
    }

    // MARK: - Public API

    /// Verifies recording policy for a venue using AI web search
    /// - Parameters:
    ///   - name: Venue name (e.g., "Target", "Walmart")
    ///   - address: Optional address for context
    ///   - types: Google Places types for context
    ///   - forceRefresh: If true, ignores cache
    /// - Returns: AI verification result
    func verifyPolicy(
        name: String,
        address: String? = nil,
        types: [String] = [],
        forceRefresh: Bool = false
    ) async throws -> AIVerificationResult {
        let cacheKey = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Check cache first
        if !forceRefresh {
            if let cached = getCachedResult(for: cacheKey), !cached.isStale {
                print("[AI Policy] Cache hit for '\(name)'")
                return cached
            }
        }

        // Try Gemini first (with Google Search grounding)
        if let geminiKey = geminiKeyProvider() {
            do {
                let result = try await verifyWithGemini(name: name, address: address, types: types, apiKey: geminiKey)
                cacheResult(result, for: cacheKey)
                return result
            } catch {
                print("[AI Policy] Gemini failed: \(error.localizedDescription), trying fallback...")
            }
        }

        // Try Perplexity as fallback
        if let perplexityKey = perplexityKeyProvider() {
            let result = try await verifyWithPerplexity(name: name, address: address, types: types, apiKey: perplexityKey)
            cacheResult(result, for: cacheKey)
            return result
        }

        throw VerificationError.noAPIKeyAvailable
    }

    /// Batch verify multiple venues (with rate limiting)
    func batchVerify(
        venues: [(name: String, address: String?, types: [String])],
        maxConcurrent: Int = 3
    ) async -> [String: AIVerificationResult] {
        var results: [String: AIVerificationResult] = [:]

        // Process in batches to avoid rate limiting
        for batch in venues.chunked(into: maxConcurrent) {
            await withTaskGroup(of: (String, AIVerificationResult?).self) { group in
                for venue in batch {
                    group.addTask {
                        let result = try? await self.verifyPolicy(
                            name: venue.name,
                            address: venue.address,
                            types: venue.types
                        )
                        return (venue.name, result)
                    }
                }

                for await (name, result) in group {
                    if let result = result {
                        results[name] = result
                    }
                }
            }

            // Small delay between batches to avoid rate limiting
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        }

        return results
    }

    // MARK: - Gemini Implementation

    private func verifyWithGemini(
        name: String,
        address: String?,
        types: [String],
        apiKey: String
    ) async throws -> AIVerificationResult {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        // Build context string
        var context = "Business name: \(name)"
        if let address = address { context += "\nAddress: \(address)" }
        if !types.isEmpty { context += "\nBusiness type: \(types.joined(separator: ", "))" }

        let prompt = """
        Search the web and analyze whether "\(name)" (a retail/commercial business) has a photography or filming policy that restricts commercial video recording inside their stores/locations.

        Context:
        \(context)

        Look for:
        1. Official corporate policies about photography/filming
        2. Store rules or codes of conduct
        3. News articles or reports about filming restrictions
        4. General industry practices for this type of business

        Respond ONLY with valid JSON in this exact format:
        {
            "hasRestrictions": true/false,
            "confidence": 0.0-1.0,
            "summary": "Brief 1-2 sentence explanation of the policy or lack thereof"
        }

        - hasRestrictions should be true if the business has known policies restricting commercial filming
        - confidence should reflect how certain you are (1.0 = found official policy, 0.5 = only indirect evidence, 0.3 = speculation)
        - Do not include any text outside the JSON object
        """

        // Request body with Google Search grounding
        struct Part: Encodable { let text: String }
        struct Content: Encodable { let parts: [Part] }
        struct GoogleSearchTool: Encodable {}
        struct Tool: Encodable { let googleSearch: GoogleSearchTool }
        struct Body: Encodable {
            let contents: [Content]
            let tools: [Tool]
        }

        let body = Body(
            contents: [Content(parts: [Part(text: prompt)])],
            tools: [Tool(googleSearch: GoogleSearchTool())]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw VerificationError.requestFailed("Invalid response")
        }

        if http.statusCode == 429 {
            throw VerificationError.rateLimited
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw VerificationError.requestFailed("HTTP \(http.statusCode): \(body.prefix(200))")
        }

        // Parse Gemini response
        struct GLMPart: Decodable { let text: String? }
        struct GLMContent: Decodable { let parts: [GLMPart]? }
        struct GLMCandidate: Decodable { let content: GLMContent? }
        struct GLMResponse: Decodable { let candidates: [GLMCandidate]? }

        let glm = try JSONDecoder().decode(GLMResponse.self, from: data)

        guard let text = glm.candidates?.first?.content?.parts?.first?.text else {
            throw VerificationError.parseFailed
        }

        // Extract JSON from response
        guard let jsonString = extractJSON(from: text),
              let jsonData = jsonString.data(using: .utf8) else {
            print("[AI Policy] Could not extract JSON from: \(text.prefix(500))")
            throw VerificationError.parseFailed
        }

        struct PolicyResponse: Decodable {
            let hasRestrictions: Bool
            let confidence: Double
            let summary: String
        }

        let parsed = try JSONDecoder().decode(PolicyResponse.self, from: jsonData)

        return AIVerificationResult(
            hasRestrictions: parsed.hasRestrictions,
            confidence: parsed.confidence,
            summary: parsed.summary,
            sources: nil,
            timestamp: Date()
        )
    }

    // MARK: - Perplexity Implementation

    private func verifyWithPerplexity(
        name: String,
        address: String?,
        types: [String],
        apiKey: String
    ) async throws -> AIVerificationResult {
        let url = URL(string: "https://api.perplexity.ai/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        var context = "Business: \(name)"
        if let address = address { context += " at \(address)" }
        if !types.isEmpty { context += " (type: \(types.joined(separator: ", ")))" }

        let prompt = """
        Does "\(name)" have a policy that restricts commercial video recording or photography inside their stores?

        Search for their official photography/filming policy and respond with ONLY this JSON:
        {"hasRestrictions": true/false, "confidence": 0.0-1.0, "summary": "brief explanation"}
        """

        struct Message: Encodable {
            let role: String
            let content: String
        }

        struct Body: Encodable {
            let model: String
            let messages: [Message]
        }

        let body = Body(
            model: "sonar",  // Perplexity's search-enabled model
            messages: [
                Message(role: "system", content: "You are a research assistant. Respond only with valid JSON."),
                Message(role: "user", content: prompt)
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw VerificationError.requestFailed("Invalid response")
        }

        if http.statusCode == 429 {
            throw VerificationError.rateLimited
        }

        guard (200..<300).contains(http.statusCode) else {
            throw VerificationError.requestFailed("HTTP \(http.statusCode)")
        }

        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        struct PerplexityResponse: Decodable {
            let choices: [Choice]
            let citations: [String]?
        }

        let parsed = try JSONDecoder().decode(PerplexityResponse.self, from: data)

        guard let content = parsed.choices.first?.message.content,
              let jsonString = extractJSON(from: content),
              let jsonData = jsonString.data(using: .utf8) else {
            throw VerificationError.parseFailed
        }

        struct PolicyResponse: Decodable {
            let hasRestrictions: Bool
            let confidence: Double
            let summary: String
        }

        let policy = try JSONDecoder().decode(PolicyResponse.self, from: jsonData)

        return AIVerificationResult(
            hasRestrictions: policy.hasRestrictions,
            confidence: policy.confidence,
            summary: policy.summary,
            sources: parsed.citations,
            timestamp: Date()
        )
    }

    // MARK: - Helpers

    private func extractJSON(from text: String) -> String? {
        // Find JSON object in response
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        for i in text[start...].indices {
            let ch = text[i]
            if ch == "{" { depth += 1 }
            if ch == "}" {
                depth -= 1
                if depth == 0 { return String(text[start...i]) }
            }
        }
        return nil
    }

    private func getCachedResult(for key: String) -> AIVerificationResult? {
        cacheQueue.sync { cache[key] }
    }

    private func cacheResult(_ result: AIVerificationResult, for key: String) {
        cacheQueue.async { self.cache[key] = result }
    }

    func clearCache() {
        cacheQueue.async { self.cache.removeAll() }
    }
}


// MARK: - Array Extension

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
