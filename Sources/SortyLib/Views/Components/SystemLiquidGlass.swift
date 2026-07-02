import SwiftUI

extension View {
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
