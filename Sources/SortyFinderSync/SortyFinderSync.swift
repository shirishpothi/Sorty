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
        let mascotImage = Self.finderMascotImage()

        switch menuKind {
        case .contextualMenuForItems, .contextualMenuForContainer:
            let organizeItem = NSMenuItem(
                title: "Organize with Sorty",
                action: #selector(organizeAction(_:)),
                keyEquivalent: ""
            )
            organizeItem.image = mascotImage
            organizeItem.target = self
            menu.addItem(organizeItem)
        case .toolbarItemMenu:
            let organizeItem = NSMenuItem(
                title: "Organize Folder",
                action: #selector(organizeAction(_:)),
                keyEquivalent: ""
            )
            organizeItem.image = mascotImage
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

    private static func finderMascotImage() -> NSImage {
        if let image = NSImage(named: "SortyMascotTemplate") ?? NSImage(named: "SortyMascot") {
            image.isTemplate = true
            return image
        }

        if let directURL = Bundle.main.url(forResource: "SortyMascotTemplate", withExtension: "svg"),
           let image = NSImage(contentsOf: directURL) {
            image.isTemplate = true
            return image
        }

        if let resourceURL = Bundle.main.resourceURL {
            let bundledCandidates = [
                resourceURL.appendingPathComponent("SortyLib_SortyLib.bundle/SortyMascotTemplate.svg"),
                resourceURL.appendingPathComponent("SortyMascotTemplate.svg")
            ]

            for candidate in bundledCandidates {
                if let image = NSImage(contentsOf: candidate) {
                    image.isTemplate = true
                    return image
                }
            }
        }

        let fallback = NSImage(systemSymbolName: "folder.fill.badge.gearshape", accessibilityDescription: "Sorty")
            ?? NSImage(size: NSSize(width: 16, height: 16))
        fallback.isTemplate = true
        return fallback
    }
}
