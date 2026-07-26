import SwiftUI

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
            .padding(3)
            .systemLiquidGlassBackground(cornerRadius: 999)
        }
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
                    selectionBubble
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
    private var selectionBubble: some View {
        Color.clear
            .systemLiquidGlassBackground(cornerRadius: 999)
            .matchedGeometryEffect(id: "selection", in: selectionNamespace)
            .padding(.horizontal, isDraggingSelection ? -2 : 0)
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

}
