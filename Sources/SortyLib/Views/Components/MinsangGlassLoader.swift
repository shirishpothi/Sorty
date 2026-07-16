import SwiftUI

/// The recovered Minsang Glass Loader, scaled for compact progress surfaces.
struct MinsangGlassLoader: View {
    let textChangeTrigger: String
    var size: CGFloat = 54
    var isActive = true

    @Environment(\.colorScheme) private var colorScheme
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
    private static let dispersion: Float = 0
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
                let loader = Circle()
                    .trim(from: 0.06, to: 0.86)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.82),
                                Color.white,
                                Color.white.opacity(0.22),
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(
                            lineWidth: max(min(proxy.size.width, proxy.size.height) * 0.06, 2),
                            lineCap: .round
                        )
                    )
                    .padding(max(min(proxy.size.width, proxy.size.height) * 0.12, 4))
                    .rotationEffect(.radians(time * Double(Self.ringSpeed)))
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .layerEffect(
                        inkShader(
                            library: shaderLibrary,
                            time: time,
                            size: proxy.size
                        ),
                        maxSampleOffset: CGSize(width: 48, height: 48)
                    )

                if colorScheme == .dark {
                    loader.blendMode(.screen)
                } else {
                    loader
                        .colorInvert()
                        .blendMode(.multiply)
                }
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
        guard let url = resourceURL(
            named: "MinsangGlassLoader",
            extension: "metallib",
            subdirectory: "Shaders"
        ) else {
            return nil
        }
        return ShaderLibrary(url: url)
    }()

    /// Resolves a copied resource across bundle layouts. A stale nested
    /// `Sorty_SortyLib.bundle` inside an installed app can win the
    /// `SortyResources.bundle` lookup while the shipped resources live
    /// flattened in the app's `Contents/Resources`, so always fall back
    /// to `Bundle.main`.
    private static func resourceURL(
        named name: String,
        extension ext: String,
        subdirectory: String
    ) -> URL? {
        for bundle in [SortyResources.bundle, Bundle.main] {
            if let url = bundle.url(
                forResource: name,
                withExtension: ext,
                subdirectory: subdirectory
            ) {
                return url
            }
            if let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }
}

private extension MinsangGlassLoader {
    enum LoaderPhase: Int {
        case base
        case dual
        case merge
    }
}
