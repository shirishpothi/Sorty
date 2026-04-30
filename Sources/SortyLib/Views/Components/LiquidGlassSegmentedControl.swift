import SwiftUI

private struct LiquidGlassSegmentBubbleShape: Shape {
    let topLeading: CGFloat
    let bottomLeading: CGFloat
    let bottomTrailing: CGFloat
    let topTrailing: CGFloat

    func path(in rect: CGRect) -> Path {
        let tl = max(0, min(min(topLeading, rect.width / 2), rect.height / 2))
        let bl = max(0, min(min(bottomLeading, rect.width / 2), rect.height / 2))
        let br = max(0, min(min(bottomTrailing, rect.width / 2), rect.height / 2))
        let tr = max(0, min(min(topTrailing, rect.width / 2), rect.height / 2))

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
            radius: tr,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(
            center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
            radius: br,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
            radius: bl,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(
            center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
            radius: tl,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct LiquidGlassSegmentFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct LiquidGlassSegmentedControl<Option: Hashable, Label: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private let options: [Option]
    @Binding private var selection: Option
    private let equalWidth: Bool
    private let minSegmentHeight: CGFloat
    private let label: (Option, Bool) -> Label

    @Namespace private var selectionNamespace
    @State private var segmentFrames: [Int: CGRect] = [:]
    @GestureState private var isDraggingSelection = false

    private let coordinateSpaceName = "LiquidGlassSegmentedControl"
    private let segmentSpacing: CGFloat = 2
    private let cornerRadius: CGFloat = 10

    init(
        selection: Binding<Option>,
        options: [Option],
        equalWidth: Bool = true,
        minSegmentHeight: CGFloat = 20,
        @ViewBuilder label: @escaping (Option, Bool) -> Label
    ) {
        self._selection = selection
        self.options = options
        self.equalWidth = equalWidth
        self.minSegmentHeight = minSegmentHeight
        self.label = label
    }

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                liquidGlassControl
            } else {
                fallbackPicker
            }
        }
    }

    @available(macOS 26.0, *)
    private var liquidGlassControl: some View {
        GlassEffectContainer(spacing: segmentSpacing) {
            HStack(spacing: segmentSpacing) {
                ForEach(Array(options.indices), id: \.self) { index in
                    segmentButton(for: index)
                }
            }
        }
        .padding(2)
        .coordinateSpace(name: coordinateSpaceName)
        .onPreferenceChange(LiquidGlassSegmentFramesPreferenceKey.self) { segmentFrames = $0 }
        .simultaneousGesture(dragSelectionGesture)
    }

    private var fallbackPicker: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.self) { option in
                label(option, selection == option)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @available(macOS 26.0, *)
    private func segmentButton(for index: Int) -> some View {
        let option = options[index]
        let isSelected = selection == option

        return Button {
            select(option)
        } label: {
            ZStack {
                if isSelected {
                    selectionBubble(for: index)
                }

                label(option, isSelected)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? selectedTextColor : defaultTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: equalWidth ? .infinity : nil)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .frame(minHeight: minSegmentHeight)
            }
            .contentShape(Capsule(style: .continuous))
            .background(segmentFrameReader(for: index))
        }
        .buttonStyle(.plain)
        .minimumHitTarget(minSegmentHeight)
    }

    @available(macOS 26.0, *)
    private func selectionBubble(for index: Int) -> some View {
        Group {
            if isDraggingSelection {
                Color.clear
                    .glassEffect(
                        colorScheme == .dark
                            ? .regular.tint(Color.white.opacity(0.08)).interactive()
                            : .regular.tint(Color.white.opacity(0.03)).interactive(),
                        in: bubbleShape(for: index)
                    )
            } else {
                bubbleShape(for: index)
                    .fill(solidSelectionFillColor)
                    .overlay {
                        bubbleShape(for: index)
                            .stroke(solidSelectionStrokeColor, lineWidth: 1)
                    }
            }
        }
            .matchedGeometryEffect(id: "selection", in: selectionNamespace)
            .padding(edgePadding(for: index))
    }

    @available(macOS 26.0, *)
    private func bubbleShape(for index: Int) -> LiquidGlassSegmentBubbleShape {
        let outerRadius = cornerRadius + 4
        let innerRadius = max(cornerRadius - 4.5, 5)

        if options.count <= 1 {
            return LiquidGlassSegmentBubbleShape(
                topLeading: outerRadius,
                bottomLeading: outerRadius,
                bottomTrailing: outerRadius,
                topTrailing: outerRadius
            )
        }

        if index == options.startIndex {
            return LiquidGlassSegmentBubbleShape(
                topLeading: outerRadius,
                bottomLeading: outerRadius,
                bottomTrailing: innerRadius,
                topTrailing: innerRadius
            )
        }

        if index == options.indices.last {
            return LiquidGlassSegmentBubbleShape(
                topLeading: innerRadius,
                bottomLeading: innerRadius,
                bottomTrailing: outerRadius,
                topTrailing: outerRadius
            )
        }

        return LiquidGlassSegmentBubbleShape(
            topLeading: innerRadius,
            bottomLeading: innerRadius,
            bottomTrailing: innerRadius,
            topTrailing: innerRadius
        )
    }

    @available(macOS 26.0, *)
    private func edgePadding(for index: Int) -> EdgeInsets {
        EdgeInsets(
            top: 0,
            leading: index == options.startIndex ? -3 : 0,
            bottom: 0,
            trailing: index == options.indices.last ? -3 : 0
        )
    }

    @available(macOS 26.0, *)
    private func segmentFrameReader(for index: Int) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: LiquidGlassSegmentFramesPreferenceKey.self,
                value: [index: proxy.frame(in: .named(coordinateSpaceName))]
            )
        }
    }

    @available(macOS 26.0, *)
    private var dragSelectionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .updating($isDraggingSelection) { _, state, _ in
                state = true
            }
            .onChanged { value in
                guard let option = option(at: value.location) else { return }
                select(option)
            }
    }

    @available(macOS 26.0, *)
    private func option(at point: CGPoint) -> Option? {
        options.indices.first { index in
            segmentFrames[index]?.contains(point) == true
        }.map { index in
            options[index]
        }
    }

    private func select(_ option: Option) {
        guard selection != option else { return }

        HapticFeedbackManager.shared.selection()
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            selection = option
        }
    }

    private var selectedTextColor: Color {
        colorScheme == .dark ? Color.white : Color.primary
    }

    private var defaultTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.74) : Color.primary.opacity(0.68)
    }

    private var solidSelectionFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }

    private var solidSelectionStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.14)
    }
}
