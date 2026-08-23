import Foundation

public enum PermisoPanel: String, CaseIterable, Sendable {
    case fullDiskAccess = "Privacy_AllFiles"
    case automation = "Privacy_Automation"
    case notifications = "Notifications"

    public var title: String {
        switch self {
        case .fullDiskAccess:
            "Full Disk Access"
        case .automation:
            "Automation"
        case .notifications:
            "Notifications"
        }
    }

    public var supportsAppDrop: Bool {
        switch self {
        case .fullDiskAccess:
            true
        case .automation, .notifications:
            false
        }
    }

    var guideSymbol: String {
        switch self {
        case .fullDiskAccess:
            "externaldrive.fill.badge.checkmark"
        case .automation:
            "gearshape.2.fill"
        case .notifications:
            "bell.badge.fill"
        }
    }

    func guideInstruction(appName: String) -> String {
        switch self {
        case .automation:
            return "Find \(appName), then turn on Finder"
        case .notifications:
            return "Turn on Allow notifications for \(appName)"
        case .fullDiskAccess:
            return "Drag \(appName) to the list above"
        }
    }

    public var settingsURL: URL {
        let urlString: String
        switch self {
        case .notifications:
            let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.sorty.app"
            urlString = "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleIdentifier)"
        default:
            urlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(rawValue)"
        }

        guard let url = URL(string: urlString) else {
            preconditionFailure("Invalid System Settings URL for \(rawValue)")
        }
        return url
    }
}
