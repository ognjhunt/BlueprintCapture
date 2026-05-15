import Foundation

struct CaptureHandoffRoute: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case universalLink
        case customScheme
    }

    let handoff: String
    let source: Source
    let sourceURL: URL

    static func parse(url: URL) -> CaptureHandoffRoute? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let handoff = components.queryItems?.first(where: { $0.name == "handoff" })?.value,
              handoff.isEmpty == false else {
            return nil
        }

        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased()
        let path = url.path.lowercased()

        if scheme == "blueprintcapture" || scheme == "blueprint" {
            guard host == "capture" else { return nil }
            return CaptureHandoffRoute(handoff: handoff, source: .customScheme, sourceURL: url)
        }

        if scheme == "https", path == "/capture/open" {
            return CaptureHandoffRoute(handoff: handoff, source: .universalLink, sourceURL: url)
        }

        return nil
    }
}

struct CaptureHandoffMetadata: Equatable, Sendable, Decodable {
    static let defaultPrivacyReminder = "Capture only approved areas. Avoid private, restricted, or sensitive content."

    let requestId: String
    let captureJobId: String
    let targetName: String
    let addressLabel: String
    let captureBrief: String?
    let privacyReminder: String
    let allowedAdvisoryHints: [String]
    let truthBoundary: String

    enum CodingKeys: String, CodingKey {
        case requestId
        case requestIdSnake = "request_id"
        case captureJobId
        case captureJobIdSnake = "capture_job_id"
        case targetName
        case targetNameSnake = "target_name"
        case addressLabel
        case addressLabelSnake = "address_label"
        case captureBrief
        case captureBriefSnake = "capture_brief"
        case privacyReminder
        case privacyReminderSnake = "privacy_reminder"
        case allowedAdvisoryHints
        case allowedAdvisoryHintsSnake = "allowed_advisory_hints"
        case truthBoundary
        case truthBoundarySnake = "truth_boundary"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try container.decodeString(.requestId, .requestIdSnake)
        captureJobId = try container.decodeString(.captureJobId, .captureJobIdSnake)
        targetName = try container.decodeString(.targetName, .targetNameSnake)
        addressLabel = try container.decodeString(.addressLabel, .addressLabelSnake)
        captureBrief = try container.decodeOptionalString(.captureBrief, .captureBriefSnake)
        privacyReminder = try container.decodeOptionalString(.privacyReminder, .privacyReminderSnake) ?? Self.defaultPrivacyReminder
        allowedAdvisoryHints = try container.decodeOptionalStrings(.allowedAdvisoryHints, .allowedAdvisoryHintsSnake) ?? []
        truthBoundary = try container.decodeOptionalString(.truthBoundary, .truthBoundarySnake) ?? MetaDisplayHUDSnapshot.truthBoundary
    }
}

final class CaptureHandoffClient {
    enum ClientError: Error, Equatable {
        case missingBaseURL
        case invalidResponse(statusCode: Int)
    }

    private let baseURLProvider: () -> URL?
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURLProvider: @escaping () -> URL? = {
        AppConfig.backendBaseURL() ?? AppConfig.mainWebsiteURL()
    }, session: URLSession = .shared) {
        self.baseURLProvider = baseURLProvider
        self.session = session
        self.decoder = JSONDecoder()
    }

    func endpointURL(for route: CaptureHandoffRoute) throws -> URL {
        guard let baseURL = baseURLProvider() ?? Self.baseURL(from: route.sourceURL) else {
            throw ClientError.missingBaseURL
        }
        return baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("requests")
            .appendingPathComponent("capture-handoff")
            .appendingPathComponent(route.handoff)
    }

    func fetchMetadata(for route: CaptureHandoffRoute) async throws -> CaptureHandoffMetadata {
        var request = URLRequest(url: try endpointURL(for: route))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ios", forHTTPHeaderField: "X-Blueprint-Native-Client")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse(statusCode: -1)
        }
        guard http.statusCode == 200 else {
            throw ClientError.invalidResponse(statusCode: http.statusCode)
        }
        return try decoder.decode(CaptureHandoffMetadata.self, from: data)
    }

    private static func baseURL(from url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https",
              let host = url.host,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        components.host = host
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

@MainActor
final class CaptureHandoffService {
    static let shared = CaptureHandoffService()

    private let client: CaptureHandoffClient

    init(client: CaptureHandoffClient = CaptureHandoffClient()) {
        self.client = client
    }

    @discardableResult
    func handle(url: URL) -> Bool {
        guard let route = CaptureHandoffRoute.parse(url: url) else { return false }
        Task { await resolve(route: route) }
        return true
    }

    private func resolve(route: CaptureHandoffRoute) async {
        do {
            let metadata = try await client.fetchMetadata(for: route)
            open(metadata: metadata, route: route)
        } catch {
            NotificationCenter.default.post(
                name: .blueprintCaptureHandoffFailed,
                object: nil,
                userInfo: [
                    "handoff": route.handoff,
                    "error": error.localizedDescription
                ]
            )
        }
    }

    private func open(metadata: CaptureHandoffMetadata, route: CaptureHandoffRoute) {
        NotificationCenter.default.post(name: .blueprintOpenTab, object: nil, userInfo: ["tab": "scan"])
        NotificationCenter.default.post(name: .blueprintOpenScanJobDetail, object: nil, userInfo: [
            "jobId": metadata.captureJobId,
            "requestId": metadata.requestId,
            "handoff": route.handoff,
            "handoffMetadata": metadata
        ])
    }
}

private extension KeyedDecodingContainer where Key == CaptureHandoffMetadata.CodingKeys {
    func decodeString(_ camelKey: Key, _ snakeKey: Key) throws -> String {
        if let value = try decodeIfPresent(String.self, forKey: camelKey), value.isEmpty == false {
            return value
        }
        return try decode(String.self, forKey: snakeKey)
    }

    func decodeOptionalString(_ camelKey: Key, _ snakeKey: Key) throws -> String? {
        if let value = try decodeIfPresent(String.self, forKey: camelKey), value.isEmpty == false {
            return value
        }
        if let value = try decodeIfPresent(String.self, forKey: snakeKey), value.isEmpty == false {
            return value
        }
        return nil
    }

    func decodeOptionalStrings(_ camelKey: Key, _ snakeKey: Key) throws -> [String]? {
        if let value = try decodeIfPresent([String].self, forKey: camelKey) {
            return value
        }
        return try decodeIfPresent([String].self, forKey: snakeKey)
    }
}

extension Notification.Name {
    static let blueprintCaptureHandoffFailed = Notification.Name("Blueprint.CaptureHandoffFailed")
}
