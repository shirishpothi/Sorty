import AppKit
import SwiftUI

public struct AppKitImageView: NSViewRepresentable {
    public enum Scaling {
        case fit
        case fill

        fileprivate var imageScaling: NSImageScaling {
            switch self {
            case .fit:
                return .scaleProportionallyUpOrDown
            case .fill:
                return .scaleAxesIndependently
            }
        }
    }

    private let image: NSImage
    private let size: CGSize
    private let scaling: Scaling
    private let cornerRadius: CGFloat
    private let opacity: CGFloat

    public init(
        image: NSImage,
        size: CGSize,
        scaling: Scaling = .fit,
        cornerRadius: CGFloat = 0,
        opacity: CGFloat = 1
    ) {
        self.image = image
        self.size = size
        self.scaling = scaling
        self.cornerRadius = cornerRadius
        self.opacity = opacity
    }

    public func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView(frame: CGRect(origin: .zero, size: size))
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = scaling.imageScaling
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = cornerRadius > 0 || opacity < 1
        imageView.layer?.cornerRadius = cornerRadius
        imageView.layer?.masksToBounds = cornerRadius > 0
        imageView.alphaValue = opacity
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.image = image
        return imageView
    }

    public func updateNSView(_ imageView: NSImageView, context: Context) {
        if imageView.image !== image {
            imageView.image = image
        }
        imageView.imageScaling = scaling.imageScaling
        imageView.alphaValue = opacity
        imageView.wantsLayer = cornerRadius > 0 || opacity < 1
        imageView.layer?.cornerRadius = cornerRadius
        imageView.layer?.masksToBounds = cornerRadius > 0
    }
}
