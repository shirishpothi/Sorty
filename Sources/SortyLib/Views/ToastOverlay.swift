//
//  ToastOverlay.swift
//  Sorty
//
//  A reusable toast notification view.
//

import SwiftUI

enum ToastKind {
    case info
    case success
    case warning
    case error
    case copied

    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .copied: return "doc.on.doc.fill"
        }
    }

    var color: Color {
        switch self {
        case .info: return SortyDesignSystem.Colors.resolvedAccent
        case .success: return .green
        case .warning: return .orange
        case .error: return SortyDesignSystem.Colors.error
        case .copied: return .teal
        }
    }
}

struct ToastOverlay: View {
    let message: String
    var kind: ToastKind = .info
    let actionLabel: String?
    let action: (() -> Void)?
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false
    @State private var dismissalID = UUID()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(kind.color)
                .frame(width: 28, height: 28)
                .systemLiquidGlassBackground(cornerRadius: 14)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let label = actionLabel, let action = action {
                Spacer()
                Button {
                    HapticFeedbackManager.shared.tap()
                    action()
                } label: {
                    Text(label)
                        .bold()
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .systemLiquidGlassBackground(cornerRadius: 12)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(kind.color.opacity(0.18), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: kind.color.opacity(0.10), radius: 12, x: 0, y: 6)
        .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 5)
        .padding(.bottom, 20)
        .opacity(isPresented ? 1 : 0)
        .offset(y: reduceMotion ? 0 : (isPresented ? 0 : 16))
        .onAppear {
            let id = UUID()
            dismissalID = id

            withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.82)) {
                isPresented = true
            }

            playHaptic()

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard dismissalID == id else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9)) {
                    isPresented = false
                }
                try? await Task.sleep(nanoseconds: reduceMotion ? 0 : 250_000_000)
                guard dismissalID == id else { return }
                onDismiss()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }

    private func playHaptic() {
        switch kind {
        case .success, .copied:
            HapticFeedbackManager.shared.success()
        case .warning:
            HapticFeedbackManager.shared.tap()
        case .error:
            HapticFeedbackManager.shared.error()
        case .info:
            HapticFeedbackManager.shared.selection()
        }
    }
}

struct CometLoader<S: Shape>: View {
    var shape: S
    var size: CGFloat = 18
    var lineWidth: CGFloat = 2
    var color: Color = SortyDesignSystem.Colors.resolvedAccent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        shape: S,
        size: CGFloat = 18,
        lineWidth: CGFloat = 2,
        color: Color = SortyDesignSystem.Colors.resolvedAccent
    ) {
        self.shape = shape
        self.size = size
        self.lineWidth = lineWidth
        self.color = color
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, canvasSize in
                let rect = CGRect(origin: .zero, size: canvasSize).insetBy(dx: lineWidth, dy: lineWidth)
                let path = shape.path(in: rect)

                context.stroke(
                    path,
                    with: .color(color.opacity(0.16)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )

                let phase = reduceMotion ? 0.18 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
                let head = CGFloat(phase)
                let tail = max(0, head - 0.28)
                let cometPath = path.trimmedPath(from: tail, to: head)

                context.stroke(
                    cometPath,
                    with: .linearGradient(
                        Gradient(colors: [
                            color.opacity(0.05),
                            color.opacity(0.55),
                            color
                        ]),
                        startPoint: CGPoint(x: rect.minX, y: rect.midY),
                        endPoint: CGPoint(x: rect.maxX, y: rect.midY)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension CometLoader where S == Circle {
    init(size: CGFloat = 18, lineWidth: CGFloat = 2, color: Color = SortyDesignSystem.Colors.resolvedAccent) {
        self.init(shape: Circle(), size: size, lineWidth: lineWidth, color: color)
    }
}
