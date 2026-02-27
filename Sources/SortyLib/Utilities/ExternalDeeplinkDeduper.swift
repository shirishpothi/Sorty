import Foundation

@MainActor
public enum ExternalDeeplinkDeduper {
    private static var lastSignature: String = ""
    private static var lastHandledAt: Date = .distantPast
    private static let dedupeWindow: TimeInterval = 0.8

    public static func shouldHandle(_ url: URL) -> Bool {
        let signature = url.absoluteString
        let now = Date()

        if signature == lastSignature, now.timeIntervalSince(lastHandledAt) < dedupeWindow {
            return false
        }

        lastSignature = signature
        lastHandledAt = now
        return true
    }
}
