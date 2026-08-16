#if DEBUG
import SwiftUI

// MARK: - Xcode previews
//
// These are DEBUG-only showcases of every size × palette × theme combo so a
// contributor editing the shader can see the visual effect of their changes
// directly in the Xcode canvas. None of this code ships in Release builds.

#Preview("md Colorful dark")    { BeamPreviewCard(size: .medium, palette: .colorful, theme: .dark) }
#Preview("md Colorful light")   { BeamPreviewCard(size: .medium, palette: .colorful, theme: .light) }
#Preview("sm Sunset dark")      { BeamPreviewCard(size: .small,  palette: .sunset,   theme: .dark) }
#Preview("line Ocean dark")     { BeamPreviewCard(size: .line,   palette: .ocean,    theme: .dark) }
#Preview("line Colorful light") { BeamPreviewCard(size: .line,   palette: .colorful, theme: .light) }

/// Single helper that renders the appropriate sample shape for each size and
/// wraps it in a themed background. Keeps each `#Preview` to one line.
private struct BeamPreviewCard: View {
    let size: BeamSize
    let palette: BeamPalette
    let theme: BeamTheme

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            sample
                .beam(size, palette: palette, theme: theme)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    private var backgroundColor: Color {
        theme == .dark ? .black : .white
    }

    private var cardFill: Color {
        theme == .dark ? Color(white: 0.08) : Color(white: 0.95)
    }

    private var canvasSize: CGSize {
        switch size {
        case .medium, .comet: return CGSize(width: 800, height: 400)
        case .small:  return CGSize(width: 400, height: 250)
        case .line:   return CGSize(width: 800, height: 300)
        }
    }

    @ViewBuilder
    private var sample: some View {
        switch size {
        case .medium, .comet: mediumSample
        case .small:  smallSample
        case .line:   lineSample
        }
    }

    private var mediumSample: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(cardFill)
            .frame(width: 370, height: 90)
            .overlay(alignment: .leading) {
                Text("Build anything…")
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
    }

    private var smallSample: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(cardFill)
            .frame(width: 70, height: 36)
            .overlay {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
    }

    private var lineSample: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(cardFill)
            .frame(width: 320, height: 40)
            .overlay(alignment: .leading) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
            }
    }
}
#endif
