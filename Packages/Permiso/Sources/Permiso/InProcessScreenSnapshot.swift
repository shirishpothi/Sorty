import AppKit
import Foundation

enum InProcessScreenSnapshot {
    @MainActor
    static func capture(screenRect: CGRect) -> NSImage? {
        let targetRect = screenRect.integral
        guard !targetRect.isEmpty else { return nil }

        for window in NSApp.windows where window.isVisible && !window.isMiniaturized {
            guard let contentView = window.contentView else { continue }
            guard window.frame.intersects(targetRect) else { continue }

            let rectInWindow = window.convertFromScreen(targetRect)
            let rectInContent = contentView.convert(rectInWindow, from: nil).intersection(contentView.bounds)
            guard !rectInContent.isEmpty else { continue }
            guard let representation = contentView.bitmapImageRepForCachingDisplay(in: rectInContent) else { continue }

            contentView.cacheDisplay(in: rectInContent, to: representation)

            let image = NSImage(size: rectInContent.size)
            image.addRepresentation(representation)
            return image
        }

        return nil
    }
}
