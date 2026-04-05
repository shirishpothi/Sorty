//
//  AboutView.swift
//  Sorty
//
//  About dialog with liquid glass styling
//

import SwiftUI

struct AboutView: View {
    private let sponsorsURL = URL(string: "https://github.com/sponsors/shirishpothi")!
    private let docsURL = URL(string: "https://github.com/shirishpothi/Sorty#readme")!
    private let githubURL = URL(string: "https://github.com/shirishpothi/Sorty")!

    @State private var supportHovered = false
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
                if BuildInfo.hasValidCommit,
                   let commitURL = URL(string: "https://github.com/shirishpothi/Sorty/commit/\(BuildInfo.commit)") {
                    Button {
                        HapticFeedbackManager.shared.tap()
                        NSWorkspace.shared.open(commitURL)
                    } label: {
                        Text("Commit \(BuildInfo.shortCommit)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("AboutCommitButton")
                    .trackHoveredURL(commitURL)
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
            VStack(spacing: 12) {
                Button {
                    HapticFeedbackManager.shared.tap()
                    NSWorkspace.shared.open(sponsorsURL)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                        Text("Support the Developer")
                            .foregroundStyle(.white)
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.vertical, 2)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .trackHoveredURL(sponsorsURL)
                .scaleEffect(supportHovered ? 1.04 : 1.0)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) { supportHovered = hovering }
                    if hovering { HapticFeedbackManager.shared.selection() }
                }

                HStack(spacing: 12) {
                    Button("Docs") {
                        HapticFeedbackManager.shared.tap()
                        NSWorkspace.shared.open(docsURL)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .trackHoveredURL(docsURL)
                    .scaleEffect(docsHovered ? 1.04 : 1.0)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) { docsHovered = hovering }
                        if hovering { HapticFeedbackManager.shared.selection() }
                    }
                    
                    Button("GitHub") {
                        HapticFeedbackManager.shared.tap()
                        NSWorkspace.shared.open(githubURL)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .trackHoveredURL(githubURL)
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
                .controlSize(.large)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
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
        .padding(26)
        .frame(width: 390, height: 470)
        .modifier(AboutGlassBackground())
        .windowLinkHoverPillHost()
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
