//
//  SettingsComponents.swift
//  Sorty
//
//  Shared settings UI components
//

import SwiftUI

private struct SettingsFocusTargetKey: EnvironmentKey {
    static let defaultValue: SettingsFocusTarget? = nil
}

extension EnvironmentValues {
    var settingsFocusTarget: SettingsFocusTarget? {
        get { self[SettingsFocusTargetKey.self] }
        set { self[SettingsFocusTargetKey.self] = newValue }
    }
}

private struct SettingsFocusableModifier: ViewModifier {
    @Environment(\.settingsFocusTarget) private var focusTarget
    let target: SettingsFocusTarget

    func body(content: Content) -> some View {
        content
            .id(target.rawValue)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        focusTarget == target
                        ? Color.accentColor.opacity(0.8)
                        : Color.clear,
                        lineWidth: 2
                    )
            )
            .shadow(color: focusTarget == target ? Color.accentColor.opacity(0.2) : .clear, radius: 8, x: 0, y: 1)
            .animation(.easeInOut(duration: 0.2), value: focusTarget == target)
    }
}

struct SidebarButton: View {
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? color : .secondary)
                    .frame(width: 20)
                
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? color.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
            }
            
            content
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

struct SettingsNavigationCard: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            HapticFeedbackManager.shared.tap()
            action()
        }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.86 : 0.64))
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(isHovered ? 0.18 : 0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering && !isHovered {
                HapticFeedbackManager.shared.selection()
            }
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                content
            }
        }
    }
}

struct SettingsTextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct SettingsSecureField: View {
    let title: String
    @Binding var text: String
    var isOptional: Bool = false
    
    @State private var isShowingText = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                if isOptional {
                    Text("Optional")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if FeatureFlags.privacyModeEnabled {
                    Button {
                        guard FeatureFlags.privacyModeEnabled else {
                            isShowingText.toggle()
                            HapticFeedbackManager.shared.tap()
                            return
                        }

                        if isShowingText {
                            isShowingText = false
                            HapticFeedbackManager.shared.tap()
                            return
                        }

                        Task { @MainActor in
                            let didAuthenticate = await SecurityManager.shared.authenticateForSensitiveAction(
                                reason: "Authenticate to reveal a hidden secret."
                            )
                            guard didAuthenticate else {
                                HapticFeedbackManager.shared.error()
                                return
                            }
                            isShowingText = true
                            HapticFeedbackManager.shared.tap()
                        }
                    } label: {
                        Image(systemName: isShowingText ? "eye.slash" : "eye")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isShowingText ? "Hide API Key" : "Show API Key")
                }
            }
            
            if isShowingText && FeatureFlags.privacyModeEnabled {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
            } else {
                SecureField("", text: $text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

struct SettingsToggle: View {
    @Binding var isOn: Bool
    let title: String
    var description: String? = nil
    var previewAction: (() -> Void)? = nil
    var previewIcon: String = "speaker.wave.2.fill"
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                if let description = description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
            }
            
            Spacer()
            
            if let previewAction {
                Button(action: previewAction) {
                    Image(systemName: previewIcon)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .accessibilityIdentifier("preview\(title.replacingOccurrences(of: " ", with: ""))Button")
                .accessibilityLabel("Preview \(title)")
            }
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
        .onChange(of: isOn) { _, _ in
            HapticFeedbackManager.shared.selection()
        }
    }
}

struct URLSchemeRow: View {
    let scheme: String
    let description: String
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?
    
    var body: some View {
        HStack(spacing: 8) {
            Text(scheme)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
            
            Spacer()
            
            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(scheme, forType: .string)
                HapticFeedbackManager.shared.tap()
                resetTask?.cancel()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    copied = true
                }
                resetTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_250_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        copied = false
                    }
                }
            } label: {
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(copied ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .scaleEffect(copied ? 1.12 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: copied)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

extension View {
    @ViewBuilder
    func applyIdentifier(_ id: String?) -> some View {
        if let id = id {
            self.accessibilityIdentifier(id)
        } else {
            self
        }
    }

    func settingsFocusTarget(_ target: SettingsFocusTarget?) -> some View {
        environment(\.settingsFocusTarget, target)
    }

    func settingsFocusable(_ target: SettingsFocusTarget) -> some View {
        modifier(SettingsFocusableModifier(target: target))
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
