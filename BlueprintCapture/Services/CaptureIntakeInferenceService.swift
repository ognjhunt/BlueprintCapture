import Foundation

struct CaptureIntakeInferenceResult: Equatable {
    let intakePacket: QualificationIntakePacket
    let metadata: CaptureIntakeMetadata
    let taskHypothesis: CaptureTaskHypothesis
}

protocol CaptureIntakeInferenceServiceProtocol {
    func inferIntake(for request: CaptureUploadRequest) async throws -> CaptureIntakeInferenceResult
}

final class CaptureIntakeInferenceService: CaptureIntakeInferenceServiceProtocol {
    private struct InlineVideoPayload {
        let base64Data: String
        let mimeType: String
    }

    enum ServiceError: LocalizedError {
        case featureDisabled
        case missingAPIKey
        case missingVideo
        case unsupportedModel(String)
        case uploadFailed(String)
        case fileProcessingFailed
        case generationFailed(String)
        case invalidResponse
        case incompleteResult

        var errorDescription: String? {
            switch self {
            case .featureDisabled:
                return "AI intake generation is disabled for this alpha build."
            case .missingAPIKey:
                return "Gemini API key is not configured."
            case .missingVideo:
                return "walkthrough.mov could not be found for intake inference."
            case .unsupportedModel(let model):
                return "Gemini model \(model) is unavailable."
            case .uploadFailed(let message):
                return "Gemini file upload failed: \(message)"
            case .fileProcessingFailed:
                return "Gemini did not finish processing the video."
            case .generationFailed(let message):
                return "Gemini intake generation failed: \(message)"
            case .invalidResponse:
                return "Gemini returned an invalid intake response."
            case .incompleteResult:
                return "Gemini returned an incomplete intake."
            }
        }
    }

    private struct UploadedFileResource: Decodable {
        let name: String
        let uri: String
        let mimeType: String?
        let state: String?

        enum CodingKeys: String, CodingKey {
            case name
            case uri
            case mimeType
            case state
        }
    }

    private struct UploadedFileEnvelope: Decodable {
        let file: UploadedFileResource?
        let name: String?
        let uri: String?
        let mimeType: String?
        let state: String?

        var resource: UploadedFileResource? {
            if let file {
                return file
            }
            guard let name, let uri else { return nil }
            return UploadedFileResource(name: name, uri: uri, mimeType: mimeType, state: state)
        }
    }

    private let session: URLSession
    private let apiKeyProvider: () -> String?
    private let primaryModel = "gemini-3.1-flash-lite-preview"
    private let fallbackModel = "gemini-3-flash-preview"
    private let maxInlineVideoBytes = 70 * 1024 * 1024
    private let thinkingLevel = "HIGH"

    init(
        session: URLSession = .shared,
        apiKeyProvider: @escaping () -> String? = {
            guard RuntimeConfig.current.availability(for: .captureIntakeAI).isEnabled else { return nil }
            return DeveloperProviderOverrides.value(for: ["GEMINI_API_KEY", "GOOGLE_AI_API_KEY", "GEMINI_MAPS_API_KEY"])
        }
    ) {
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    func inferIntake(for request: CaptureUploadRequest) async throws -> CaptureIntakeInferenceResult {
        guard RuntimeConfig.current.availability(for: .captureIntakeAI).isEnabled else {
            throw ServiceError.featureDisabled
        }
        guard let apiKey = apiKeyProvider() else {
            throw ServiceError.missingAPIKey
        }

        let videoURL = try locateVideoURL(for: request)
        let inlineVideo = try? makeInlineVideoPayload(for: videoURL)
        let models = [primaryModel, fallbackModel]
        let fpsOptions = [3, 5]
        var lastError: Error = ServiceError.invalidResponse

        for model in models {
            for fps in fpsOptions {
                do {
                    let result: CaptureIntakeInferenceResult
                    if let inlineVideo {
                        do {
                            result = try await generateInlineIntake(
                                request: request,
                                inlineVideo: inlineVideo,
                                model: model,
                                fps: fps,
                                apiKey: apiKey
                            )
                        } catch {
                            let uploadedFile = try await uploadVideo(videoURL, apiKey: apiKey)
                            let readyFile = try await waitUntilReady(file: uploadedFile, apiKey: apiKey)
                            result = try await generateIntake(
                                request: request,
                                file: readyFile,
                                model: model,
                                fps: fps,
                                apiKey: apiKey
                            )
                        }
                    } else {
                        let uploadedFile = try await uploadVideo(videoURL, apiKey: apiKey)
                        let readyFile = try await waitUntilReady(file: uploadedFile, apiKey: apiKey)
                        result = try await generateIntake(
                            request: request,
                            file: readyFile,
                            model: model,
                            fps: fps,
                            apiKey: apiKey
                        )
                    }
                    if result.intakePacket.isComplete {
                        return result
                    }
                    lastError = ServiceError.incompleteResult
                } catch let error as ServiceError {
                    lastError = error
                    if case .unsupportedModel = error {
                        break
                    }
                } catch {
                    lastError = error
                }
            }
        }

        throw lastError
    }

    private func locateVideoURL(for request: CaptureUploadRequest) throws -> URL {
        if request.packageURL.pathExtension.lowercased() == "mov" {
            return request.packageURL
        }
        let videoURL = request.packageURL.appendingPathComponent("walkthrough.mov")
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw ServiceError.missingVideo
        }
        return videoURL
    }

    private func uploadVideo(_ videoURL: URL, apiKey: String) async throws -> UploadedFileResource {
        let videoData = try Data(contentsOf: videoURL)
        let mimeType = mimeType(for: videoURL)
        let startURL = URL(string: "https://generativelanguage.googleapis.com/upload/v1beta/files")!

        var startRequest = URLRequest(url: startURL)
        startRequest.httpMethod = "POST"
        startRequest.timeoutInterval = 60
        startRequest.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        startRequest.addValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        startRequest.addValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        startRequest.addValue(String(videoData.count), forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        startRequest.addValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        startRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        startRequest.httpBody = try JSONSerialization.data(
            withJSONObject: ["file": ["display_name": videoURL.lastPathComponent]],
            options: []
        )

        let (startData, startResponse) = try await session.data(for: startRequest)
        guard let http = startResponse as? HTTPURLResponse else {
            throw ServiceError.uploadFailed("Invalid start response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: startData, encoding: .utf8) ?? "unknown"
            throw ServiceError.uploadFailed("HTTP \(http.statusCode): \(message.prefix(300))")
        }
        guard let uploadURLString = http.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let uploadURL = URL(string: uploadURLString) else {
            throw ServiceError.uploadFailed("Missing resumable upload URL")
        }

        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.timeoutInterval = 300
        uploadRequest.addValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        uploadRequest.addValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadRequest.addValue(mimeType, forHTTPHeaderField: "Content-Type")
        uploadRequest.httpBody = videoData

        let (uploadData, uploadResponse) = try await session.data(for: uploadRequest)
        guard let uploadHTTP = uploadResponse as? HTTPURLResponse else {
            throw ServiceError.uploadFailed("Invalid upload response")
        }
        guard (200..<300).contains(uploadHTTP.statusCode) else {
            let message = String(data: uploadData, encoding: .utf8) ?? "unknown"
            throw ServiceError.uploadFailed("HTTP \(uploadHTTP.statusCode): \(message.prefix(200))")
        }

        let envelope = try JSONDecoder().decode(UploadedFileEnvelope.self, from: uploadData)
        guard let file = envelope.resource else {
            throw ServiceError.uploadFailed("Missing uploaded file resource")
        }
        return file
    }

    private func waitUntilReady(file: UploadedFileResource, apiKey: String) async throws -> UploadedFileResource {
        guard let initialState = file.state?.uppercased(), initialState == "PROCESSING" else {
            return file
        }

        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let statusURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/\(file.name)")!
            var statusRequest = URLRequest(url: statusURL)
            statusRequest.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            let (data, response) = try await session.data(for: statusRequest)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                continue
            }
            let envelope = try JSONDecoder().decode(UploadedFileEnvelope.self, from: data)
            guard let latest = envelope.resource else { continue }
            let latestState = latest.state?.uppercased() ?? "ACTIVE"
            if latestState == "ACTIVE" {
                return latest
            }
            if latestState == "FAILED" {
                throw ServiceError.fileProcessingFailed
            }
        }

        throw ServiceError.fileProcessingFailed
    }

    private func generateIntake(
        request: CaptureUploadRequest,
        file: UploadedFileResource,
        model: String,
        fps: Int,
        apiKey: String
    ) async throws -> CaptureIntakeInferenceResult {
        let body = makeGenerationBody(request: request, file: file, fps: fps, model: model, includeSchema: true)
        do {
            return try await performGeneration(body: body, model: model, fps: fps, apiKey: apiKey)
        } catch let error as ServiceError {
            guard case .generationFailed(let message) = error,
                  message.contains("responseSchema") || message.contains("responseJsonSchema") || message.contains("Unknown name") else {
                throw error
            }
            let fallbackBody = makeGenerationBody(request: request, file: file, fps: fps, model: model, includeSchema: false)
            return try await performGeneration(body: fallbackBody, model: model, fps: fps, apiKey: apiKey)
        }
    }

    private func generateInlineIntake(
        request: CaptureUploadRequest,
        inlineVideo: InlineVideoPayload,
        model: String,
        fps: Int,
        apiKey: String
    ) async throws -> CaptureIntakeInferenceResult {
        let body = makeInlineGenerationBody(request: request, inlineVideo: inlineVideo, fps: fps, model: model, includeSchema: true)
        do {
            return try await performGeneration(body: body, model: model, fps: fps, apiKey: apiKey)
        } catch let error as ServiceError {
            guard case .generationFailed(let message) = error,
                  message.contains("responseSchema") || message.contains("responseJsonSchema") || message.contains("Unknown name") else {
                throw error
            }
            let fallbackBody = makeInlineGenerationBody(request: request, inlineVideo: inlineVideo, fps: fps, model: model, includeSchema: false)
            return try await performGeneration(body: fallbackBody, model: model, fps: fps, apiKey: apiKey)
        }
    }

    private func performGeneration(
        body: [String: Any],
        model: String,
        fps: Int,
        apiKey: String
    ) async throws -> CaptureIntakeInferenceResult {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.generationFailed("Invalid response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "unknown"
            if bodyText.localizedCaseInsensitiveContains("not found") || bodyText.localizedCaseInsensitiveContains("unsupported") {
                throw ServiceError.unsupportedModel(model)
            }
            throw ServiceError.generationFailed("HTTP \(http.statusCode): \(bodyText.prefix(300))")
        }

        struct GLMPart: Decodable { let text: String? }
        struct GLMContent: Decodable { let parts: [GLMPart]? }
        struct GLMCandidate: Decodable { let content: GLMContent? }
        struct GLMResponse: Decodable { let candidates: [GLMCandidate]? }

        let glm = try JSONDecoder().decode(GLMResponse.self, from: data)
        guard let text = glm.candidates?.first?.content?.parts?.first?.text else {
            throw ServiceError.invalidResponse
        }
        guard let jsonString = extractJSONObject(from: text) ?? extractJSONArray(from: text),
              let jsonData = jsonString.data(using: .utf8) else {
            throw ServiceError.invalidResponse
        }

        struct Payload: Decodable {
            let workflowName: String?
            let taskSteps: [String]?
            let targetKPI: String?
            let zone: String?
            let shift: String?
            let owner: String?
            let adjacentSystems: [String]?
            let privacySecurityLimits: [String]?
            let knownBlockers: [String]?
            let nonRoutineModes: [String]?
            let peopleTrafficNotes: [String]?
            let captureRestrictions: [String]?
            let confidence: Double?
            let warnings: [String]?
        }

        let payload = try JSONDecoder().decode(Payload.self, from: jsonData)
        let packet = QualificationIntakePacket(
            workflowName: payload.workflowName,
            taskSteps: payload.taskSteps ?? [],
            targetKPI: payload.targetKPI,
            zone: payload.zone,
            shift: payload.shift,
            owner: payload.owner,
            adjacentSystems: payload.adjacentSystems ?? [],
            privacySecurityLimits: payload.privacySecurityLimits ?? [],
            knownBlockers: payload.knownBlockers ?? [],
            nonRoutineModes: payload.nonRoutineModes ?? [],
            peopleTrafficNotes: payload.peopleTrafficNotes ?? [],
            captureRestrictions: payload.captureRestrictions ?? []
        )

        return CaptureIntakeInferenceResult(
            intakePacket: packet,
            metadata: CaptureIntakeMetadata(
                source: .aiInferred,
                model: model,
                fps: fps,
                confidence: payload.confidence,
                warnings: payload.warnings ?? []
            ),
            taskHypothesis: CaptureTaskHypothesis(
                packet: packet,
                metadata: CaptureIntakeMetadata(
                    source: .aiInferred,
                    model: model,
                    fps: fps,
                    confidence: payload.confidence,
                    warnings: payload.warnings ?? []
                ),
                status: .accepted
            )
        )
    }

    private func makeGenerationBody(
        request: CaptureUploadRequest,
        file: UploadedFileResource,
        fps: Int,
        model: String,
        includeSchema: Bool
    ) -> [String: Any] {
        let contextHint = request.metadata.captureContextHint?.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = """
        You are inferring a structured workflow intake packet from a capture walkthrough video for local pipeline testing.

        Requirements:
        - Infer the most plausible workflow name.
        - Infer ordered task steps from the visible walkthrough.
        - Ensure at least one of zone or owner is populated. Prefer zone if it can be inferred from the environment or context hint.
        - Keep speculative business-only fields conservative.
        - Respond with JSON only.

        Known metadata:
        - capture_source: \(request.metadata.captureSource.rawValue)
        - scene_id_hint: \(CaptureBundleContext.sceneIdentifier(for: request))
        - capture_context_hint: \(contextHint?.isEmpty == false ? contextHint! : "none")
        """

        let parts: [[String: Any]] = [
            ["text": prompt],
            [
                "fileData": [
                    "mimeType": file.mimeType ?? "video/mov",
                    "fileUri": file.uri
                ],
                "videoMetadata": [
                    "fps": fps
                ]
            ]
        ]

        var body: [String: Any] = [
            "contents": [
                [
                    "parts": parts
                ]
            ],
            "generationConfig": generationConfig(for: model, includeSchema: includeSchema)
        ]

        return body
    }

    private func makeInlineGenerationBody(
        request: CaptureUploadRequest,
        inlineVideo: InlineVideoPayload,
        fps: Int,
        model: String,
        includeSchema: Bool
    ) -> [String: Any] {
        let contextHint = request.metadata.captureContextHint?.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = """
        You are inferring a structured workflow intake packet from a capture walkthrough video for local pipeline testing.

        Requirements:
        - Infer the most plausible workflow name.
        - Infer ordered task steps from the visible walkthrough.
        - Ensure at least one of zone or owner is populated. Prefer zone if it can be inferred from the environment or context hint.
        - Keep speculative business-only fields conservative.
        - Respond with JSON only.

        Known metadata:
        - capture_source: \(request.metadata.captureSource.rawValue)
        - scene_id_hint: \(CaptureBundleContext.sceneIdentifier(for: request))
        - capture_context_hint: \(contextHint?.isEmpty == false ? contextHint! : "none")
        """

        let parts: [[String: Any]] = [
            [
                "inlineData": [
                    "mimeType": inlineVideo.mimeType,
                    "data": inlineVideo.base64Data
                ],
                "videoMetadata": [
                    "fps": fps
                ]
            ],
            ["text": prompt]
        ]

        var body: [String: Any] = [
            "contents": [
                [
                    "parts": parts
                ]
            ],
            "generationConfig": generationConfig(for: model, includeSchema: includeSchema)
        ]

        return body
    }

    private func generationConfig(for model: String, includeSchema: Bool) -> [String: Any] {
        var config: [String: Any] = [
            "responseMimeType": "application/json"
        ]

        if model.hasPrefix("gemini-3") {
            config["thinkingConfig"] = [
                "thinkingLevel": thinkingLevel
            ]
        }

        if includeSchema {
            config["responseSchema"] = [
                "type": "OBJECT",
                "properties": [
                    "workflowName": ["type": "STRING"],
                    "taskSteps": ["type": "ARRAY", "items": ["type": "STRING"]],
                    "targetKPI": ["type": "STRING"],
                    "zone": ["type": "STRING"],
                    "shift": ["type": "STRING"],
                    "owner": ["type": "STRING"],
                    "adjacentSystems": ["type": "ARRAY", "items": ["type": "STRING"]],
                    "privacySecurityLimits": ["type": "ARRAY", "items": ["type": "STRING"]],
                    "knownBlockers": ["type": "ARRAY", "items": ["type": "STRING"]],
                    "nonRoutineModes": ["type": "ARRAY", "items": ["type": "STRING"]],
                    "peopleTrafficNotes": ["type": "ARRAY", "items": ["type": "STRING"]],
                    "captureRestrictions": ["type": "ARRAY", "items": ["type": "STRING"]],
                    "confidence": ["type": "NUMBER"],
                    "warnings": ["type": "ARRAY", "items": ["type": "STRING"]]
                ],
                "required": ["workflowName", "taskSteps"]
            ]
        }

        return config
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mov":
            return "video/mov"
        case "mp4":
            return "video/mp4"
        default:
            return "application/octet-stream"
        }
    }

    private func makeInlineVideoPayload(for url: URL) throws -> InlineVideoPayload? {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize, fileSize > 0, fileSize <= maxInlineVideoBytes else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return InlineVideoPayload(
            base64Data: data.base64EncodedString(),
            mimeType: mimeType(for: url)
        )
    }

    private func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        for index in text[start...].indices {
            let character = text[index]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
        }
        return nil
    }

    private func extractJSONArray(from text: String) -> String? {
        guard let start = text.firstIndex(of: "[") else { return nil }
        var depth = 0
        for index in text[start...].indices {
            let character = text[index]
            if character == "[" { depth += 1 }
            if character == "]" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
        }
        return nil
    }
}
