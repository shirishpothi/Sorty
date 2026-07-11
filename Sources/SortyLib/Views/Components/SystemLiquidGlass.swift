import AppKit
import SwiftUI

/// Backdrop that samples and displays content *behind the window* (desktop,
/// other apps), like Finder's sidebar. Liquid glass alone cannot do this:
/// `glassEffect` only samples content inside the window, so pair this backdrop
/// with a `.clear` glass effect layered above it.
private struct BehindWindowBackdropView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .underWindowBackground
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension View {
    /// Uses the native interactive Liquid Glass button style on macOS 26,
    /// while preserving Sorty's compact secondary pill on older systems.
    @ViewBuilder
    func systemLiquidGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            self
                .buttonStyle(.glass)
                .tint(nil)
        } else {
            self.buttonStyle(.onboardingPill(isSecondary: true, size: .small))
        }
    }

    /// Liquid glass that shows through to content behind the window.
    /// Falls back to a plain behind-window material before macOS 26.
    @ViewBuilder
    func behindWindowLiquidGlassBackground(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            self.background {
                BehindWindowBackdropView()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .glassEffect(.clear.interactive(), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self.background {
                BehindWindowBackdropView()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
    }

    @ViewBuilder
    func systemLiquidGlassBackground(cornerRadius: CGFloat, clear: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.clear)
                    .glassEffect(
                        clear ? .clear.interactive() : .regular.interactive(),
                        in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func systemLiquidGlassPopover(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            self
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.clear)
                        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                }
                .presentationBackground(.clear)
                .presentationCornerRadius(cornerRadius)
        } else {
            self.presentationCornerRadius(cornerRadius)
        }
    }
}
