import Foundation

public protocol ProviderHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionProviderTransport: ProviderHTTPTransport {
    public init() {}

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await NetworkPrivacyPolicy.sharedSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudProviderIntegrationError.invalidResponse
        }
        return (data, httpResponse)
    }
}

public enum CloudProviderIntegrationError: LocalizedError, Sendable {
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)
    case privacyModeBlocked

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The storage provider returned an invalid response."
        case .requestFailed(let statusCode, let message):
            return "The storage provider rejected the request (\(statusCode)): \(message)"
        case .privacyModeBlocked:
            return NetworkPrivacyPolicy.blockedMessage
        }
    }
}

public struct GoogleDriveItem: Codable, Hashable, Sendable {
    public let id: String
    public let name: String?
    public let mimeType: String?
    public let starred: Bool?
    public let parents: [String]?

    public init(
        id: String,
        name: String? = nil,
        mimeType: String? = nil,
        starred: Bool? = nil,
        parents: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.starred = starred
        self.parents = parents
    }
}

public struct GoogleDriveIntegration: Sendable {
    private let accessToken: String
    private let transport: any ProviderHTTPTransport
    private let baseURL = URL(string: "https://www.googleapis.com/drive/v3")!

    public init(
        accessToken: String,
        transport: any ProviderHTTPTransport = URLSessionProviderTransport()
    ) {
        self.accessToken = accessToken
        self.transport = transport
    }

    public func setStarred(_ starred: Bool, fileID: String) async throws -> GoogleDriveItem {
        try await metadataRequest(
            path: "files/\(encodedPathComponent(fileID))",
            method: "PATCH",
            queryItems: [
                URLQueryItem(name: "supportsAllDrives", value: "true"),
                URLQueryItem(name: "fields", value: "id,name,mimeType,starred,parents"),
            ],
            body: ["starred": starred]
        )
    }

    public func createFolder(name: String, parentID: String) async throws -> GoogleDriveItem {
        try await metadataRequest(
            path: "files",
            method: "POST",
            queryItems: [
                URLQueryItem(name: "supportsAllDrives", value: "true"),
                URLQueryItem(name: "fields", value: "id,name,mimeType,starred,parents"),
            ],
            body: [
                "name": name,
                "mimeType": "application/vnd.google-apps.folder",
                "parents": [parentID],
            ]
        )
    }

    public func moveItem(
        fileID: String,
        fromParentID: String,
        toParentID: String
    ) async throws -> GoogleDriveItem {
        try await metadataRequest(
            path: "files/\(encodedPathComponent(fileID))",
            method: "PATCH",
            queryItems: [
                URLQueryItem(name: "addParents", value: toParentID),
                URLQueryItem(name: "removeParents", value: fromParentID),
                URLQueryItem(name: "supportsAllDrives", value: "true"),
                URLQueryItem(name: "fields", value: "id,name,mimeType,starred,parents"),
            ],
            body: [:]
        )
    }

    public func createShortcut(
        name: String,
        targetID: String,
        parentID: String
    ) async throws -> GoogleDriveItem {
        try await metadataRequest(
            path: "files",
            method: "POST",
            queryItems: [
                URLQueryItem(name: "supportsAllDrives", value: "true"),
                URLQueryItem(name: "fields", value: "id,name,mimeType,starred,parents"),
            ],
            body: [
                "name": name,
                "mimeType": "application/vnd.google-apps.shortcut",
                "parents": [parentID],
                "shortcutDetails": ["targetId": targetID],
            ]
        )
    }

    private func metadataRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        body: [String: Any]
    ) async throws -> GoogleDriveItem {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = queryItems
        guard let url = components.url else {
            throw CloudProviderIntegrationError.invalidResponse
        }
        guard NetworkPrivacyPolicy.isRequestAllowed(url: url) else {
            throw CloudProviderIntegrationError.privacyModeBlocked
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw CloudProviderIntegrationError.requestFailed(
                statusCode: response.statusCode,
                message: Self.errorMessage(from: data)
            )
        }
        return try JSONDecoder().decode(GoogleDriveItem.self, from: data)
    }

    private func encodedPathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return "Unknown provider error"
        }
        return message
    }
}
