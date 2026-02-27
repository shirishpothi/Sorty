import Foundation

public struct WindowLaunchRequest: Codable, Hashable, Identifiable {
    public let id: UUID
    public let deeplinkURLString: String?

    public init(id: UUID = UUID(), deeplinkURLString: String? = nil) {
        self.id = id
        self.deeplinkURLString = deeplinkURLString
    }

    public init(url: URL) {
        self.init(deeplinkURLString: url.absoluteString)
    }

    public var deeplinkURL: URL? {
        guard let deeplinkURLString, !deeplinkURLString.isEmpty else {
            return nil
        }
        return URL(string: deeplinkURLString)
    }
}
