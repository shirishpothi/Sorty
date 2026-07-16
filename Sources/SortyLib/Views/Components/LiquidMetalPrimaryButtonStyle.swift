import MetalKit
import SwiftUI
import simd

/// The recovered Minsang liquid-metal shader, adapted to Sorty's primary action pill.
struct LiquidMetalPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var isPaused: Bool

    init(isPaused: Bool = false) {
        self.isPaused = isPaused
    }

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed

        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background {
                LiquidMetalButtonSurface(
                    isPaused: isPaused || !isEnabled || reduceMotion,
                    isIntensified: isHovering || isPressed
                )
            }
            .contentShape(Capsule())
            .shadow(
                color: Self.accentColor.opacity(isEnabled ? (isHovering ? 0.30 : 0.18) : 0.04),
                radius: isPressed ? 4 : (isHovering ? 12 : 8),
                y: isPressed ? 1 : (isHovering ? 5 : 3)
            )
            .scaleEffect(isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(isEnabled ? 1 : 0.56)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isPressed)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    HapticFeedbackManager.shared.selection()
                }
            }
            .onChange(of: isPressed) { _, newValue in
                if newValue {
                    HapticFeedbackManager.shared.tap()
                }
            }
    }

    private static let accentColor = Color(red: 188 / 255, green: 52 / 255, blue: 78 / 255)
}

private struct LiquidMetalButtonSurface: View {
    let isPaused: Bool
    let isIntensified: Bool

    private static let accent = SIMD3<Float>(188 / 255, 52 / 255, 78 / 255)
    private static let light = SIMD3<Float>(200 / 255, 55 / 255, 83 / 255)

    var body: some View {
        ZStack {
            Color(red: 188 / 255, green: 52 / 255, blue: 78 / 255)

            LiquidMetalRenderView(
                isPaused: isPaused,
                rotation: isIntensified ? SIMD2(0.08, -0.025) : .zero,
                baseColor: Self.accent,
                accentColor: Self.accent,
                lightColor: Self.light
            )
            .opacity(isIntensified ? 0.50 : 0.42)

            LinearGradient(
                colors: [
                    .white.opacity(isIntensified ? 0.08 : 0.05),
                    .clear,
                    .black.opacity(isIntensified ? 0.12 : 0.18),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.10), location: 0.28),
                    .init(color: .black.opacity(isIntensified ? 0.22 : 0.28), location: 0.50),
                    .init(color: .black.opacity(0.10), location: 0.72),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.34), .white.opacity(0.08), .black.opacity(0.24)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
        .clipShape(Capsule())
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct LiquidMetalRenderView: NSViewRepresentable {
    let isPaused: Bool
    let rotation: SIMD2<Float>
    let baseColor: SIMD3<Float>
    let accentColor: SIMD3<Float>
    let lightColor: SIMD3<Float>

    func makeCoordinator() -> LiquidMetalRenderer {
        LiquidMetalRenderer(parent: self)
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = context.coordinator.device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = clearColor
        view.preferredFramesPerSecond = 30
        view.enableSetNeedsDisplay = isPaused
        view.isPaused = isPaused
        view.delegate = context.coordinator
        if isPaused {
            view.draw()
        }
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.parent = self
        view.clearColor = clearColor
        view.enableSetNeedsDisplay = isPaused
        view.isPaused = isPaused
        if isPaused {
            view.draw()
        }
    }

    private var clearColor: MTLClearColor {
        MTLClearColor(
            red: Double(baseColor.x),
            green: Double(baseColor.y),
            blue: Double(baseColor.z),
            alpha: 1
        )
    }
}

private final class LiquidMetalRenderer: NSObject, MTKViewDelegate {
    var parent: LiquidMetalRenderView
    let device: MTLDevice?

    private let commandQueue: MTLCommandQueue?
    private let pipelineState: MTLRenderPipelineState?
    private var time: Float = 0
    private var lastTime: CFTimeInterval = 0
    private var currentRotation = SIMD2<Float>.zero

    init(parent: LiquidMetalRenderView) {
        self.parent = parent

        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        commandQueue = device?.makeCommandQueue()

        if
            let device,
            let libraryURL = Self.shaderLibraryURL,
            let library = try? device.makeLibrary(URL: libraryURL),
            let vertexFunction = library.makeFunction(name: "wwd_vertex"),
            let fragmentFunction = library.makeFunction(name: "wwd_fragment")
        {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
        } else {
            pipelineState = nil
        }

        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard
            let drawable = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor,
            let pipelineState,
            let commandBuffer = commandQueue?.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        let now = CACurrentMediaTime()
        let delta = lastTime > 0 ? Float(now - lastTime) : 1 / 60
        lastTime = now
        if !parent.isPaused {
            time += delta
        }
        currentRotation += min(delta * 10, 1) * (parent.rotation - currentRotation)

        // A square projection stretches the recovered donut across the pill,
        // turning its liquid-metal ring into a full-width button surface.
        let projection = perspectiveMatrix(aspect: 1)
        let translation = translationMatrix(z: -4)
        let rotationX = rotationMatrix(angle: currentRotation.y, axis: SIMD3<Float>(1, 0, 0))
        let rotationY = rotationMatrix(angle: currentRotation.x, axis: SIMD3<Float>(0, 1, 0))
        let model = translation * rotationX * rotationY

        var uniforms = LiquidMetalUniforms(
            inverseProjection: projection.inverse,
            inverseModel: model.inverse,
            time: time,
            waveAmplitude: 0.1,
            waveFrequency: 10,
            baseDistortion: 0.01,
            reflectionStrength: 40,
            dispersion: 5,
            iridescence: 60,
            viewportWidth: Float(view.drawableSize.width),
            viewportHeight: Float(view.drawableSize.height),
            touchStrength: 1,
            waveAngle: 0.78,
            donutThickness: 0,
            baseColor: SIMD4(parent.baseColor, 0),
            accentColor: SIMD4(parent.accentColor, 0),
            lightColor: SIMD4(parent.lightColor, 0),
            lightPosition: SIMD4(-1, 2, 2, 0)
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<LiquidMetalUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<LiquidMetalUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private static let shaderLibraryURL: URL? = {
        for bundle in [SortyResources.bundle, Bundle.main] {
            if let url = bundle.url(
                forResource: "MinsangGlassLoader",
                withExtension: "metallib",
                subdirectory: "Shaders"
            ) {
                return url
            }
            if let url = bundle.url(forResource: "MinsangGlassLoader", withExtension: "metallib") {
                return url
            }
        }
        return nil
    }()

    private func perspectiveMatrix(aspect: Float) -> simd_float4x4 {
        let y = Float(1.7321)
        let z = Float(-1.001)
        let wz = Float(-0.1001)
        return simd_float4x4(columns: (
            SIMD4(y / aspect, 0, 0, 0),
            SIMD4(0, y, 0, 0),
            SIMD4(0, 0, z, -1),
            SIMD4(0, 0, wz, 0)
        ))
    }

    private func translationMatrix(z: Float) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(0, 0, z, 1)
        ))
    }

    private func rotationMatrix(angle: Float, axis: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle: angle, axis: axis))
    }
}

private struct LiquidMetalUniforms {
    var inverseProjection = matrix_identity_float4x4
    var inverseModel = matrix_identity_float4x4
    var time: Float = 0
    var waveAmplitude: Float = 0.1
    var waveFrequency: Float = 10
    var baseDistortion: Float = 0.01
    var reflectionStrength: Float = 40
    var dispersion: Float = 5
    var iridescence: Float = 60
    var viewportWidth: Float = 1
    var viewportHeight: Float = 1
    var touchStrength: Float = 1
    var waveAngle: Float = 0.78
    var donutThickness: Float = 0
    var baseColor = SIMD4<Float>(1, 1, 1, 0)
    var accentColor = SIMD4<Float>(1, 1, 1, 0)
    var lightColor = SIMD4<Float>(1, 1, 1, 0)
    var colorPadding = SIMD4<Float>.zero
    var lightPosition = SIMD4<Float>(-1, 2, 2, 0)
    var tailPadding = SIMD4<Float>.zero
}

extension ButtonStyle where Self == LiquidMetalPrimaryButtonStyle {
    static func liquidMetalPrimary(isPaused: Bool = false) -> LiquidMetalPrimaryButtonStyle {
        LiquidMetalPrimaryButtonStyle(isPaused: isPaused)
    }
}
