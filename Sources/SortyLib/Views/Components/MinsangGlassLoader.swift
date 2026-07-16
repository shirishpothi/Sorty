import SwiftUI

/// The recovered Minsang Glass Loader, scaled for compact progress surfaces.
struct MinsangGlassLoader: View {
    let textChangeTrigger: String
    var size: CGFloat = 28
    var isActive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = LoaderPhase.base
    @State private var hasPresented = false
    @State private var nextAlternatePhase = LoaderPhase.dual

    private static let circleFraction: Float = 0.32
    private static let dotFraction: Float = 0.08
    private static let dotCount: Float = 6
    private static let moverSpeed: Float = 1.6
    private static let ringSpeed: Float = 0.45
    private static let threshold: Float = 1.38
    private static let refraction: Float = 14
    private static let dispersion: Float = 3
    private static let distortion: Float = 4
    private static let distortionSpread: Float = 1
    private static let border: Float = 0.5

    /// The recovered mover speed is expressed in radians per second.
    private static let fullTurnDuration = (2 * Double.pi) / Double(moverSpeed)

    private var shouldAnimate: Bool {
        isActive && !reduceMotion
    }

    var body: some View {
        Group {
            if let shaderLibrary = Self.shaderLibrary {
                glassLoader(shaderLibrary: shaderLibrary)
            } else {
                CometLoader(size: size, lineWidth: 2, color: .secondary)
            }
        }
        .frame(width: size, height: size)
        .task(id: textChangeTrigger) {
            guard hasPresented else {
                hasPresented = true
                return
            }
            guard shouldAnimate else {
                phase = .base
                return
            }

            phase = nextAlternatePhase
            nextAlternatePhase = nextAlternatePhase == .dual ? .merge : .dual

            do {
                try await Task.sleep(for: .seconds(Self.fullTurnDuration))
                phase = .base
            } catch {
                // A newer text change owns the next full-turn phase.
            }
        }
        .onChange(of: reduceMotion) { _, isReduced in
            if isReduced {
                phase = .base
            }
        }
        .accessibilityHidden(true)
    }

    private func glassLoader(shaderLibrary: ShaderLibrary) -> some View {
        SwiftUI.TimelineView(
            .animation(minimumInterval: 1.0 / 30.0, paused: !shouldAnimate)
        ) { timeline in
            GeometryReader { proxy in
                let time = shouldAnimate ? timeline.date.timeIntervalSinceReferenceDate : 0
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                Color.accentColor.opacity(0.82),
                                Color.primary.opacity(0.72),
                                Color.pink.opacity(0.72),
                                Color.accentColor.opacity(0.82),
                            ],
                            center: .center
                        )
                    )
                    .layerEffect(
                        inkShader(
                            library: shaderLibrary,
                            time: time,
                            size: proxy.size
                        ),
                        maxSampleOffset: CGSize(
                            width: proxy.size.width * 48 / 380,
                            height: proxy.size.height * 48 / 380
                        )
                    )
            }
        }
    }

    private func inkShader(
        library: ShaderLibrary,
        time: TimeInterval,
        size: CGSize
    ) -> Shader {
        ShaderFunction(library: library, name: "ink")
            .dynamicallyCall(withArguments: [
                .float(time.truncatingRemainder(dividingBy: 100)),
                .float2(size),
                .float(Self.circleFraction),
                .float(Self.dotFraction),
                .float(Self.dotCount),
                .float(Self.moverSpeed),
                .float(Self.ringSpeed),
                .float(Self.threshold),
                .float(Self.refraction),
                .float(Self.dispersion),
                .float(Self.distortion),
                .float(Self.distortionSpread),
                .float(Self.border),
                .float(Float(phase.rawValue)),
            ])
    }

    private static let shaderLibrary: ShaderLibrary? = {
        guard let url = SortyResources.bundle.url(
            forResource: "MinsangGlassLoader",
            withExtension: "metallib",
            subdirectory: "Shaders"
        ) else {
            return nil
        }
        return ShaderLibrary(url: url)
    }()
}

private extension MinsangGlassLoader {
    enum LoaderPhase: Int {
        case base
        case dual
        case merge
    }
}
