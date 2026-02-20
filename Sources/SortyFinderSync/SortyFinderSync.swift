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
        let organizeImage = Self.normalizedMenuIcon(Self.finderOrganizeImage(), isTemplate: false)
        let watchImage = Self.normalizedMenuIcon(Self.finderWatchImage(), isTemplate: true)

        switch menuKind {
        case .contextualMenuForItems, .contextualMenuForContainer:
            let organizeItem = NSMenuItem(
                title: "Organize with Sorty",
                action: #selector(organizeAction(_:)),
                keyEquivalent: ""
            )
            organizeItem.image = organizeImage
            organizeItem.target = self
            menu.addItem(organizeItem)

            let watchItem = NSMenuItem(
                title: "Watch with Sorty",
                action: #selector(watchAction(_:)),
                keyEquivalent: ""
            )
            watchItem.image = watchImage
            watchItem.target = self
            menu.addItem(watchItem)
        case .toolbarItemMenu:
            let organizeItem = NSMenuItem(
                title: "Organize Folder",
                action: #selector(organizeAction(_:)),
                keyEquivalent: ""
            )
            organizeItem.image = organizeImage
            organizeItem.target = self
            menu.addItem(organizeItem)

            let watchItem = NSMenuItem(
                title: "Watch Folder",
                action: #selector(watchAction(_:)),
                keyEquivalent: ""
            )
            watchItem.image = watchImage
            watchItem.target = self
            menu.addItem(watchItem)
        case .contextualMenuForSidebar:
            break
        @unknown default:
            break
        }

        return menu
    }

    @objc private func organizeAction(_ sender: AnyObject?) {
        _ = sender

        guard let url = Self.selectedDirectoryURL() else { return }
        guard let organizeURL = Self.urlForOrganizing(path: url.path) else { return }

        NSWorkspace.shared.open(organizeURL)
    }

    @objc private func watchAction(_ sender: AnyObject?) {
        _ = sender

        guard let url = Self.selectedDirectoryURL() else { return }
        guard let watchURL = Self.urlForWatching(path: url.path) else { return }

        NSWorkspace.shared.open(watchURL)
    }

    private static func selectedDirectoryURL() -> URL? {
        let selectedURLs = FIFinderSyncController.default().selectedItemURLs() ?? []
        let targetURL = FIFinderSyncController.default().targetedURL()

        guard let rawURL = selectedURLs.first ?? targetURL else { return nil }
        return normalizedDirectoryURL(for: rawURL)
    }

    private static func normalizedDirectoryURL(for url: URL) -> URL {
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
           values.isDirectory == false {
            return url.deletingLastPathComponent()
        }
        return url
    }

    private static func urlForOrganizing(path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "sorty"
        components.host = "organize"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url
    }

    private static func urlForWatching(path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "sorty"
        components.host = "watched"
        components.queryItems = [
            URLQueryItem(name: "action", value: "add"),
            URLQueryItem(name: "path", value: path)
        ]
        return components.url
    }

    private static func finderOrganizeImage() -> NSImage {
        // Prefer the PNG mascot head — it renders cleanly at small menu sizes.
        if let imageURL = Bundle.main.url(forResource: "SortyMascotHead", withExtension: "png"),
           let image = NSImage(contentsOf: imageURL) {
            image.isTemplate = false
            return image
        }

        // Prefer the dedicated mascot head icon supplied for Finder context menus.
        if let imageURL = Bundle.main.url(forResource: "SortyMascotHead", withExtension: "icns"),
           let image = NSImage(contentsOf: imageURL) {
            image.isTemplate = false
            return image
        }

        if let imageURL = Bundle.main.url(forResource: "Sorty Mascot Head", withExtension: "icns"),
           let image = NSImage(contentsOf: imageURL) {
            image.isTemplate = false
            return image
        }

        if let resourceURL = Bundle.main.resourceURL {
            let hostAppResourcesURL = Bundle.main.bundleURL
                .deletingLastPathComponent() // PlugIns
                .deletingLastPathComponent() // Contents
                .appendingPathComponent("Resources", isDirectory: true)

            let bundledCandidates = [
                resourceURL.appendingPathComponent("SortyMascotHead.png"),
                resourceURL.appendingPathComponent("SortyMascotHead.icns"),
                hostAppResourcesURL.appendingPathComponent("SortyMascotHead.png"),
                hostAppResourcesURL.appendingPathComponent("SortyMascotHead.icns"),
            ]

            for candidate in bundledCandidates {
                if let image = NSImage(contentsOf: candidate) {
                    image.isTemplate = false
                    return image
                }
            }
        }

        let fallback = NSImage(systemSymbolName: "folder.fill.badge.gearshape", accessibilityDescription: "Sorty")
            ?? NSImage(size: NSSize(width: 16, height: 16))
        fallback.isTemplate = true
        return fallback
    }

    private static func finderWatchImage() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        if let symbol = NSImage(systemSymbolName: "eye", accessibilityDescription: "Watch") {
            let configured = symbol.withSymbolConfiguration(config) ?? symbol
            configured.isTemplate = true
            return configured
        }
        let fallback = NSImage(size: NSSize(width: 16, height: 16))
        fallback.isTemplate = true
        return fallback
    }

    private static func normalizedMenuIcon(_ image: NSImage, isTemplate: Bool) -> NSImage {
        let menuIconSize = NSSize(width: 16, height: 16)
        let sourceImage = (image.copy() as? NSImage) ?? image

        // Fit into the menu icon size preserving aspect ratio for both template and non-template images.
        let sourceSize = sourceImage.size
        let maxDimension = max(sourceSize.width, sourceSize.height, 1)
        let scale = min(menuIconSize.width, menuIconSize.height) / maxDimension
        let drawSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let drawRect = NSRect(
            x: (menuIconSize.width - drawSize.width) / 2,
            y: (menuIconSize.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )

        let rendered = NSImage(size: menuIconSize)
        rendered.lockFocus()
        sourceImage.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        rendered.unlockFocus()
        rendered.isTemplate = isTemplate
        return rendered
    }
}
