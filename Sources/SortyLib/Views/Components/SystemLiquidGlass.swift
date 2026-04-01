import SwiftUI

extension View {
    @ViewBuilder
    func systemLiquidGlassBackground(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            self
        }
    }

    @ViewBuilder
    func systemLiquidGlassPopover(cornerRadius: CGFloat) -> some View {
        self.presentationCornerRadius(cornerRadius)
    }
}
