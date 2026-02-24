import Cocoa
import FinderSync

final class SortyFinderSync: FIFinderSync {
    override init() {
        super.init()

        let finderSync = FIFinderSyncController.default()

        if let mountedVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: .skipHiddenVolumes
        ) {
            finderSync.directoryURLs = Set(mountedVolumes)
        }

        finderSync.directoryURLs.insert(FileManager.default.homeDirectoryForCurrentUser)
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu()

        switch menuKind {
        case .contextualMenuForItems, .contextualMenuForContainer:
            let organizeItem = NSMenuItem(
                title: "Organize with Sorty",
                action: #selector(organizeAction(_:)),
                keyEquivalent: ""
            )
            organizeItem.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
            organizeItem.target = self
            menu.addItem(organizeItem)
        case .toolbarItemMenu:
            let organizeItem = NSMenuItem(
                title: "Organize Folder",
                action: #selector(organizeAction(_:)),
                keyEquivalent: ""
            )
            organizeItem.target = self
            menu.addItem(organizeItem)
        case .contextualMenuForSidebar:
            break
        @unknown default:
            break
        }

        return menu
    }

    @objc private func organizeAction(_ sender: AnyObject?) {
        _ = sender

        let selectedURLs = FIFinderSyncController.default().selectedItemURLs() ?? []
        let targetURL = FIFinderSyncController.default().targetedURL()

        let directoryURL: URL?
        if let firstSelected = selectedURLs.first {
            directoryURL = firstSelected
        } else {
            directoryURL = targetURL
        }

        guard let url = directoryURL else { return }
        guard let organizeURL = Self.urlForOrganizing(path: url.path) else { return }

        NSWorkspace.shared.open(organizeURL)
    }

    private static func urlForOrganizing(path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "sorty"
        components.host = "organize"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url
    }
}
