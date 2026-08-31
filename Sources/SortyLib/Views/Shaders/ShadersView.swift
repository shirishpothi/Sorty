import AppKit
import Combine
import SwiftUI

public struct ShadersView: View {
    @SortyHotReload private var hotReload
    @State private var selection: ShaderExperiment? = .glassLoader

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(ShaderExperiment.allCases, selection: $selection) { experiment in
                Label(experiment.title, systemImage: experiment.systemImage)
                    .tag(experiment)
            }
            .navigationTitle("Shaders")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            shaderDetail(for: selection ?? .glassLoader)
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private func shaderDetail(for experiment: ShaderExperiment) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(experiment.title)
                        .font(.title2.weight(.semibold))
                    Text(experiment.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Label("Recovered", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            Group {
                switch experiment {
                case .glassLoader:
                    RecoveredGlassLoaderView()
                case .flameInGlass:
                    RecoveredFlameInGlassView()
                case .blobbyLoader:
                    RecoveredBlobbyLoaderView()
                case .liquidMetal:
                    RecoveredLiquidMetalView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private enum ShaderExperiment: String, CaseIterable, Identifiable {
    case glassLoader
    case flameInGlass
    case blobbyLoader
    case liquidMetal

    var id: Self { self }

    var title: String {
        switch self {
        case .glassLoader: "Glass Loader"
        case .flameInGlass: "(Not) Flame in Glass"
        case .blobbyLoader: "Blobby Loader"
        case .liquidMetal: "Liquid Metal"
        }
    }

    var subtitle: String {
        switch self {
        case .glassLoader:
            "Refraction and dispersion over the original sample image."
        case .flameInGlass:
            "A ray-marched flame held inside a clear glass form."
        case .blobbyLoader:
            "An organic rotating loader with adjustable distortion."
        case .liquidMetal:
            "An interactive Metal renderer with waves, reflection, and iridescence."
        }
    }

    var systemImage: String {
        switch self {
        case .glassLoader: "circle.hexagongrid.fill"
        case .flameInGlass: "flame.fill"
        case .blobbyLoader: "circle.grid.cross.fill"
        case .liquidMetal: "drop.fill"
        }
    }
}

enum RecoveredShaderResources {
    static let libraryURL = resourceURL(
        named: "MinsangGlassLoader",
        extension: "metallib"
    )

    static let shaderLibrary = libraryURL.map { ShaderLibrary(url: $0) }

    static let sampleImage: NSImage? = {
        guard let url = resourceURL(named: "MinsangShaderSample", extension: "jpg") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    static func shader(named name: String, arguments: [Shader.Argument]) -> Shader? {
        guard let shaderLibrary else { return nil }
        return ShaderFunction(library: shaderLibrary, name: name)
            .dynamicallyCall(withArguments: arguments)
    }

    private static func resourceURL(named name: String, extension ext: String) -> URL? {
        for bundle in [SortyResources.bundle, Bundle.main] {
            if let url = bundle.url(
                forResource: name,
                withExtension: ext,
                subdirectory: "Shaders"
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

private struct RecoveredGlassLoaderView: View {
    @SortyHotReload private var hotReload
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = Phase.base

    private let circleFraction: Float = 0.32
    private let dotFraction: Float = 0.08
    private let dotCount: Float = 6
    private let moverSpeed: Float = 1.6
    private let ringSpeed: Float = 0.45
    private let threshold: Float = 1.38
    private let refraction: Float = 14
    private let dispersion: Float = 3
    private let distortion: Float = 4
    private let distortionSpread: Float = 1
    private let border: Float = 0.5

    var body: some View {
        ZStack {
            Color.black

            if let sampleImage = RecoveredShaderResources.sampleImage {
                VStack(spacing: 16) {
                    SwiftUI.TimelineView(
                        .animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)
                    ) { context in
                        GeometryReader { proxy in
                            let time = reduceMotion
                                ? 0
                                : context.date.timeIntervalSinceReferenceDate

                            Image(nsImage: sampleImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .clipped()
                                .modifier(
                                    OptionalLayerEffect(
                                        shader: inkShader(time: time, size: proxy.size),
                                        maxSampleOffset: CGSize(width: 48, height: 48)
                                    )
                                )
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 500, maxHeight: 500)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Glass Loader shader over a galaxy image")

                    Picker("Phase", selection: $phase) {
                        ForEach(Phase.allCases) { phase in
                            Text(phase.label).tag(phase)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 420)
                }
                .padding(20)
            } else {
                ShaderUnavailableView()
            }
        }
    }

    private func inkShader(time: TimeInterval, size: CGSize) -> Shader? {
        RecoveredShaderResources.shader(named: "ink", arguments: [
            .float(Float(time.truncatingRemainder(dividingBy: 100))),
            .float2(size),
            .float(circleFraction),
            .float(dotFraction),
            .float(dotCount),
            .float(moverSpeed),
            .float(ringSpeed),
            .float(threshold),
            .float(refraction),
            .float(dispersion),
            .float(distortion),
            .float(distortionSpread),
            .float(border),
            .float(Float(phase.rawValue)),
        ])
    }

    private enum Phase: Int, CaseIterable, Identifiable {
        case base
        case dual
        case merge

        var id: Self { self }

        var label: String {
            switch self {
            case .base: "Base"
            case .dual: "Dual"
            case .merge: "Merge"
            }
        }
    }
}

private struct RecoveredFlameInGlassView: View {
    @SortyHotReload private var hotReload
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cameraScale: Float = 0.34
    private let noiseStrength: Float = 1
    private let glowStrength: Float = 0.42
    private let xPosition: Float = 0

    var body: some View {
        ZStack {
            Color.black

            SwiftUI.TimelineView(
                .animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)
            ) { context in
                let time = reduceMotion
                    ? 0
                    : context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 10_000)

                flameGlass(time: time)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Flame in Glass shader")
    }

    private func flameGlass(time: TimeInterval) -> some View {
        ZStack {
            Color.black
                .frame(width: 200, height: 500)
                .modifier(
                    OptionalLayerEffect(
                        shader: RecoveredShaderResources.shader(
                            named: "loveRaymarchFlame",
                            arguments: [
                                .boundingRect,
                                .float(Float(time)),
                                .float(cameraScale),
                                .float(noiseStrength),
                                .float(glowStrength),
                                .float(xPosition),
                                .float(Float(sin(time) * 2 - 1)),
                                .float3(1, 0.5, 0.1),
                                .float3(0, 0, 1),
                            ]
                        ),
                        maxSampleOffset: .zero
                    )
                )

            Color.clear
                .frame(width: 120, height: 200)
                .systemLiquidGlassBackground(cornerRadius: 28, clear: true)

            Image(systemName: "xmark.triangle.circle.square")
                .font(.largeTitle)
                .foregroundStyle(.white)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: 500)
    }
}

private struct RecoveredBlobbyLoaderView: View {
    @SortyHotReload private var hotReload
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Float = 0
    @State private var blur = 10.0
    @State private var power = 2.0
    @State private var chromaticAberration = 4.0
    @State private var cornerRadius = 100.0

    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black

            ScrollView {
                VStack(spacing: 12) {
                    Color.white
                        .frame(width: 160, height: 160)
                        .clipShape(.rect(cornerRadius: CGFloat(cornerRadius)))
                        .frame(width: 160, height: 340)
                        .blur(radius: CGFloat(blur))
                        .modifier(
                            OptionalLayerEffect(
                                shader: RecoveredShaderResources.shader(
                                    named: "loader",
                                    arguments: [
                                        .boundingRect,
                                        .float(progress),
                                        .float(2),
                                        .float(Float(power)),
                                        .float(Float(chromaticAberration)),
                                    ]
                                ),
                                maxSampleOffset: CGSize(width: 90, height: 100)
                            )
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Animated Blobby Loader shader")

                    VStack(spacing: 10) {
                        slider("Blur", value: $blur, range: 0...40)
                        slider("Corner", value: $cornerRadius, range: 0...100)
                        slider("Power", value: $power, range: 0...10)
                        slider("Chromatic Aberration", value: $chromaticAberration, range: 0...10)
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.white)
                    .tint(.yellow)
                    .frame(maxWidth: 560)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            }
        }
        .onReceive(timer) { _ in
            guard !reduceMotion else { return }
            progress += 0.0096
        }
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 12) {
            Text("\(title): \(value.wrappedValue, specifier: "%.2f")")
                .frame(width: 190, alignment: .leading)
                .numericTextTransition(animationValue: value.wrappedValue)
            Slider(value: value, in: range)
                .accessibilityLabel(title)
                .accessibilityValue(value.wrappedValue.formatted(.number.precision(.fractionLength(2))))
        }
    }
}

private struct OptionalLayerEffect: ViewModifier {
    let shader: Shader?
    let maxSampleOffset: CGSize

    @ViewBuilder
    func body(content: Content) -> some View {
        if let shader {
            content.layerEffect(shader, maxSampleOffset: maxSampleOffset)
        } else {
            content
        }
    }
}

struct ShaderUnavailableView: View {
    @SortyHotReload private var hotReload
    var body: some View {
        ContentUnavailableView(
            "Shader Unavailable",
            systemImage: "exclamationmark.triangle",
            description: Text("The recovered Metal library could not be loaded.")
        )
        .foregroundStyle(.white)
    }
}
