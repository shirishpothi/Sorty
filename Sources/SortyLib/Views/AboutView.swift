//
//  AboutView.swift
//  Sorty
//
//  About dialog with liquid glass styling
//

import SwiftUI

struct AboutView: View {
    @State private var docsHovered = false
    @State private var githubHovered = false
    @State private var accreditationsHovered = false
    @State private var commitHovered = false
    @State private var iconHovered = false
    let openAccreditations: (() -> Void)?

    init(openAccreditations: (() -> Void)? = nil) {
        self.openAccreditations = openAccreditations
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // App Icon
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                .scaleEffect(iconHovered ? 1.05 : 1.0)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        iconHovered = hovering
                    }
                    if hovering {
                        HapticFeedbackManager.shared.selection()
                    }
                }
            
            // App Name
            Text("Sorty")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            
            // Description
            Text("Sorty: The FOSS AI File Organiser\nLearn from your patterns and keep your workspace tidy.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer().frame(height: 4)
            
            // Version Info - Centered
            VStack(spacing: 4) {
                Text("Version \(BuildInfo.version)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Text("Build \(BuildInfo.build)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                
                // Commit link
                if BuildInfo.hasValidCommit {
                    Button {
                        HapticFeedbackManager.shared.tap()
                        if let url = URL(string: "https://github.com/shirishpothi/Sorty/commit/\(BuildInfo.commit)") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("Commit \(BuildInfo.shortCommit)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("AboutCommitButton")
                    .scaleEffect(commitHovered ? 1.02 : 1.0)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) { commitHovered = hovering }
                        if hovering { HapticFeedbackManager.shared.selection() }
                    }
                } else {
                    Text("Commit \(BuildInfo.shortCommit)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer().frame(height: 8)
            
            // Buttons
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Button("Docs") {
                        HapticFeedbackManager.shared.tap()
                        if let url = URL(string: "https://github.com/shirishpothi/Sorty#readme") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .scaleEffect(docsHovered ? 1.04 : 1.0)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) { docsHovered = hovering }
                        if hovering { HapticFeedbackManager.shared.selection() }
                    }
                    
                    Button("GitHub") {
                        HapticFeedbackManager.shared.tap()
                        if let url = URL(string: "https://github.com/shirishpothi/Sorty") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .scaleEffect(githubHovered ? 1.04 : 1.0)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) { githubHovered = hovering }
                        if hovering { HapticFeedbackManager.shared.selection() }
                    }
                }

                Button("Accreditations") {
                    HapticFeedbackManager.shared.tap()
                    openAccreditations?()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("AboutAccreditationsButton")
                .scaleEffect(accreditationsHovered ? 1.04 : 1.0)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) { accreditationsHovered = hovering }
                    if hovering { HapticFeedbackManager.shared.selection() }
                }
            }
            
            Spacer().frame(height: 8)

            Text("© 2026 Shirish Pothi")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(24)
        .frame(width: 360, height: 420)
        .modifier(AboutGlassBackground())
    }
}

// MARK: - Glass Background

private struct AboutGlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background {
                    Color.clear
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 0))
                        .ignoresSafeArea()
                }
        } else {
            content.background(.ultraThinMaterial)
        }
    }
}

#Preview {
    AboutView()
}
