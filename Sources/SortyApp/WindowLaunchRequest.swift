import Foundation
#if canImport(SortyLib)
import SortyLib
#endif

struct WindowLaunchRequest: Codable, Hashable, Identifiable {
    let id: UUID
    let deeplinkURLString: String?

    init(id: UUID = UUID(), deeplinkURLString: String? = nil) {
        self.id = id
        self.deeplinkURLString = deeplinkURLString
    }

    init(url: URL) {
        self.init(deeplinkURLString: url.absoluteString)
    }

    var deeplinkURL: URL? {
        guard let deeplinkURLString, !deeplinkURLString.isEmpty else {
            return nil
        }
        return URL(string: deeplinkURLString)
    }
}
