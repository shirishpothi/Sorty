import Foundation

public enum AppDestination: Equatable {
    case organize(path: String?, persona: String?, mode: OrganizationMode?, autostart: Bool)
    case duplicates(path: String?, autostart: Bool)
    case learnings(action: LearningsAction?, project: String?)
    case settings(section: String?)
    case help(section: String?)
    case open(path: String?)
    case history
    case persona(action: String?, prompt: String?, generate: Bool)
    case watched(action: String?, path: String?)
    case rules(action: String?, type: String?, pattern: String?)
    case exclusions(action: String?, pattern: String?)
    case exclude(path: String?)
    case storage(action: String?, path: String?)

    public enum LearningsAction: String, Equatable {
        case stats
        case withdraw
        case export
        case importProfile = "import"
        case clear
    }
}

public enum LegacyDeeplinkParser {
    public static func destination(for url: URL) -> AppDestination? {
        guard FeatureFlags.legacyDeeplinksEnabled,
              url.scheme?.lowercased() == "sorty" else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        func value(_ name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }

        let host = url.host?.lowercased() ?? ""
        if host.isEmpty, url.path != "/", !url.path.isEmpty {
            return .organize(
                path: url.path.removingPercentEncoding ?? url.path,
                persona: nil,
                mode: nil,
                autostart: false
            )
        }

        switch host {
        case "organize", "scan":
            return .organize(
                path: value("path"),
                persona: value("persona"),
                mode: value("mode").flatMap(OrganizationMode.init(rawValue:)),
                autostart: host == "scan" || value("autostart") == "true"
            )
        case "duplicates":
            return .duplicates(path: value("path"), autostart: value("autostart") == "true")
        case "learnings":
            return .learnings(
                action: value("action").flatMap(AppDestination.LearningsAction.init(rawValue:)),
                project: value("project")
            )
        case "settings": return .settings(section: value("section"))
        case "help": return .help(section: value("section"))
        case "open": return .open(path: value("path"))
        case "history": return .history
        case "persona":
            return .persona(
                action: value("action"),
                prompt: value("prompt"),
                generate: value("generate") == "true"
            )
        case "watched": return .watched(action: value("action"), path: value("path"))
        case "rules":
            return .rules(action: value("action"), type: value("type"), pattern: value("pattern"))
        case "exclusions": return .exclusions(action: value("action"), pattern: value("pattern"))
        case "exclude": return .exclude(path: value("path") ?? value("pattern"))
        case "storage": return .storage(action: value("action"), path: value("path"))
        default: return nil
        }
    }
}
