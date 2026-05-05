import Foundation

public enum PermisoPanel: String, CaseIterable, Sendable {
    case accessibility = "Privacy_Accessibility"
    case fullDiskAccess = "Privacy_AllFiles"
    case automation = "Privacy_Automation"
    case screenRecording = "Privacy_ScreenCapture"

    public var title: String {
        switch self {
        case .accessibility:
            "Accessibility"
        case .fullDiskAccess:
            "Full Disk Access"
        case .automation:
            "Automation"
        case .screenRecording:
            "Screen Recording"
        }
    }

    public var settingsURL: URL {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(rawValue)") else {
            preconditionFailure("Invalid System Settings URL for \(rawValue)")
        }
        return url
    }
}
