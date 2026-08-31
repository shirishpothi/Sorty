import AppKit
import MetalKit
import QuartzCore
import simd
import SwiftUI

struct RecoveredLiquidMetalView: View {
    @SortyHotReload private var hotReload
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoom: Float = -8
    @State private var rotation = SIMD2<Float>.zero
    @State private var isShowingConfiguration = false
    @State private var waveAmplitude = 0.1
    @State private var waveFrequency = 10.0
    @State private var baseDistortion = 0.01
    @State private var reflectionStrength = 40.0
    @State private var dispersion = 5.0
    @State private var iridescence = 60.0
    @State private var speed = 1.0
    @State private var touchStrength = 1.0
    @State private var waveAngle = 0.785
    @State private var donutThickness = 0.0
    @State private var baseColor = Color.white
    @State private var accentColor = Color.white
    @State private var lightColor = Color.white

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black

            if RecoveredShaderResources.libraryURL != nil {
                RecoveredLiquidMetalRenderer(
                    zoom: zoom,
                    rotation: rotation,
                    waveAmplitude: Float(waveAmplitude),
                    waveFrequency: Float(waveFrequency),
                    baseDistortion: Float(baseDistortion),
                    reflectionStrength: Float(reflectionStrength),
                    dispersion: Float(dispersion),
                    iridescence: Float(iridescence),
                    speed: reduceMotion ? 0 : Float(speed),
                    touchStrength: Float(touchStrength),
                    waveAngle: Float(waveAngle),
                    donutThickness: Float(donutThickness),
                    baseColor: baseColor.recoveredRGB,
                    accentColor: accentColor.recoveredRGB,
                    lightColor: lightColor.recoveredRGB,
                    lightPosition: SIMD3(-1, 2, 2)
                )
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            rotation = SIMD2(
                                Float(value.translation.width * 0.01),
                                Float(value.translation.height * 0.01)
                            )
                        }
                        .onEnded { _ in
                            withAnimation(
                                reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 1)
                            ) {
                                rotation = .zero
                            }
                        }
                )
                .focusable()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Interactive Liquid Metal shader")
                .accessibilityHint("Drag to rotate the form. Use Configuration to adjust the effect.")
                .accessibilityAction(named: "Reset Rotation") {
                    rotation = .zero
                }
            } else {
                ShaderUnavailableView()
            }

            Button("Configuration", systemImage: "slider.horizontal.3") {
                isShowingConfiguration = true
                HapticFeedbackManager.shared.selection()
            }
            .systemLiquidGlassButton()
            .padding(16)
        }
        .sheet(isPresented: $isShowingConfiguration) {
            RecoveredLiquidMetalConfigurationView(
                waveAmplitude: $waveAmplitude,
                waveFrequency: $waveFrequency,
                baseDistortion: $baseDistortion,
                reflectionStrength: $reflectionStrength,
                dispersion: $dispersion,
                iridescence: $iridescence,
                speed: $speed,
                touchStrength: $touchStrength,
                waveAngle: $waveAngle,
                donutThickness: $donutThickness,
                baseColor: $baseColor,
                accentColor: $accentColor,
                lightColor: $lightColor,
                reset: resetConfiguration
            )
        }
    }

    private func resetConfiguration() {
        waveAmplitude = 0.1
        waveFrequency = 10
        baseDistortion = 0.01
        reflectionStrength = 40
        dispersion = 5
        iridescence = 60
        speed = 1
        touchStrength = 1
        waveAngle = 0.785
        donutThickness = 0
        baseColor = .white
        accentColor = .white
        lightColor = .white
        HapticFeedbackManager.shared.selection()
    }
}

private struct RecoveredLiquidMetalConfigurationView: View {
    @SortyHotReload private var hotReload
    @Binding var waveAmplitude: Double
    @Binding var waveFrequency: Double
    @Binding var baseDistortion: Double
    @Binding var reflectionStrength: Double
    @Binding var dispersion: Double
    @Binding var iridescence: Double
    @Binding var speed: Double
    @Binding var touchStrength: Double
    @Binding var waveAngle: Double
    @Binding var donutThickness: Double
    @Binding var baseColor: Color
    @Binding var accentColor: Color
    @Binding var lightColor: Color
    let reset: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Liquid Metal Configuration")
                    .font(.headline)

                Spacer()

                Button("Reset", systemImage: "arrow.counterclockwise", action: reset)
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    colorRow("Base Color", color: $baseColor)
                    colorRow("Accent Color", color: $accentColor)
                    colorRow("Light Color", color: $lightColor)
                    sliderRow("Distortion", value: $baseDistortion, range: 0...0.3)
                    sliderRow("Reflection", value: $reflectionStrength, range: 0...55)
                    sliderRow("Dispersion", value: $dispersion, range: 0...4)
                    sliderRow("Iridescence", value: $iridescence, range: 0...100)
                    sliderRow("Wave Amplitude", value: $waveAmplitude, range: 0...0.5)
                    sliderRow("Wave Frequency", value: $waveFrequency, range: 5...30)
                    sliderRow("Speed", value: $speed, range: 0...3)
                    sliderRow("Hole", value: $touchStrength, range: 0...15)
                    sliderRow("Wave Angle", value: $waveAngle, range: 0...Double.pi)
                    sliderRow("Thickness", value: $donutThickness, range: 0.05...0.8)
                }
                .padding(16)
            }
        }
        .frame(minWidth: 560, minHeight: 620)
    }

    private func sliderRow(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .fontWeight(.semibold)
                .frame(width: 125, alignment: .leading)

            Slider(value: value, in: range)
                .accessibilityLabel(label)
                .accessibilityValue(value.wrappedValue.formatted(.number.precision(.fractionLength(2))))

            Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
                .numericTextTransition(animationValue: value.wrappedValue)
        }
    }

    private func colorRow(_ label: String, color: Binding<Color>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .fontWeight(.semibold)
                .frame(width: 125, alignment: .leading)

            ColorPicker(label, selection: color, supportsOpacity: false)
                .labelsHidden()
                .accessibilityLabel(label)

            Spacer()
        }
    }
}

private struct RecoveredLiquidMetalRenderer: NSViewRepresentable {
    @SortyHotReload private var hotReload
    var zoom: Float
    var rotation: SIMD2<Float>
    var waveAmplitude: Float
    var waveFrequency: Float
    var baseDistortion: Float
    var reflectionStrength: Float
    var dispersion: Float
    var iridescence: Float
    var speed: Float
    var touchStrength: Float
    var waveAngle: Float
    var donutThickness: Float
    var baseColor: SIMD3<Float>
    var accentColor: SIMD3<Float>
    var lightColor: SIMD3<Float>
    var lightPosition: SIMD3<Float>

    func makeCoordinator() -> RecoveredLiquidMetalCoordinator {
        RecoveredLiquidMetalCoordinator(parent: self)
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = context.coordinator.device
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = clearColor
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.parent = self
        nsView.clearColor = clearColor
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

private final class RecoveredLiquidMetalCoordinator: NSObject, MTKViewDelegate {
    var parent: RecoveredLiquidMetalRenderer
    let device: MTLDevice?

    private let commandQueue: MTLCommandQueue?
    private let pipelineState: MTLRenderPipelineState?
    private var time: Float = 0
    private var lastTime: CFTimeInterval = 0
    private var currentTouchStrength: Float = 0
    private var currentRotation = SIMD2<Float>.zero

    init(parent: RecoveredLiquidMetalRenderer) {
        self.parent = parent

        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        commandQueue = device?.makeCommandQueue()

        if
            let device,
            let libraryURL = RecoveredShaderResources.libraryURL,
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
        let delta = lastTime > 0 ? Float(now - lastTime) : 0.016667
        lastTime = now
        time += delta * parent.speed
        currentTouchStrength += min(delta * 2, 1) * (parent.touchStrength - currentTouchStrength)
        currentRotation += min(delta * 10, 1) * (parent.rotation - currentRotation)

        let aspect = Float(view.drawableSize.width / max(view.drawableSize.height, 1))
        let projection = perspectiveMatrix(aspect: aspect)
        let translation = translationMatrix(z: parent.zoom)
        let rotationX = rotationMatrix(
            angle: currentRotation.y,
            axis: SIMD3<Float>(1, 0, 0)
        )
        let rotationY = rotationMatrix(
            angle: currentRotation.x,
            axis: SIMD3<Float>(0, 1, 0)
        )
        let model = translation * rotationX * rotationY

        var uniforms = RecoveredLiquidMetalUniforms(
            inverseProjection: projection.inverse,
            inverseModel: model.inverse,
            time: time,
            waveAmplitude: parent.waveAmplitude,
            waveFrequency: parent.waveFrequency,
            baseDistortion: parent.baseDistortion,
            reflectionStrength: parent.reflectionStrength,
            dispersion: parent.dispersion,
            iridescence: parent.iridescence,
            viewportWidth: Float(view.drawableSize.width),
            viewportHeight: Float(view.drawableSize.height),
            touchStrength: currentTouchStrength,
            waveAngle: parent.waveAngle,
            donutThickness: parent.donutThickness,
            baseColor: SIMD4(parent.baseColor, 0),
            accentColor: SIMD4(parent.accentColor, 0),
            lightColor: SIMD4(parent.lightColor, 0),
            lightPosition: SIMD4(parent.lightPosition, 0)
        )

        assert(MemoryLayout<RecoveredLiquidMetalUniforms>.stride == 272)
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(&uniforms, length: 272, index: 0)
        encoder.setFragmentBytes(&uniforms, length: 272, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

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

private struct RecoveredLiquidMetalUniforms {
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
    var touchStrength: Float = 0
    var waveAngle: Float = 0.785
    var donutThickness: Float = 0
    var baseColor = SIMD4<Float>(1, 1, 1, 0)
    var accentColor = SIMD4<Float>(1, 1, 1, 0)
    var lightColor = SIMD4<Float>(1, 1, 1, 0)
    var colorPadding = SIMD4<Float>.zero
    var lightPosition = SIMD4<Float>(-1, 2, 2, 0)
    var tailPadding = SIMD4<Float>.zero
}

private extension Color {
    var recoveredRGB: SIMD3<Float> {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else {
            return SIMD3(1, 1, 1)
        }
        return SIMD3(
            Float(color.redComponent),
            Float(color.greenComponent),
            Float(color.blueComponent)
        )
    }
}
