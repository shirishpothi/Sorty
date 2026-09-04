import SwiftUI

struct WindowGlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                Color.clear
                    .systemLiquidGlassBackground(cornerRadius: 0, interactive: false)
                    .ignoresSafeArea()
            }
    }
}
