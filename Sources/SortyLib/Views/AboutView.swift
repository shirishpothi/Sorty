//
//  AboutView.swift
//  Sorty
//
//  About dialog with liquid glass styling
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var docsHovered = false
    @State private var githubHovered = false
    @State private var iconHovered = false
    
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
            
            Spacer().frame(height: 8)
            
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
                    Link(destination: URL(string: "https://github.com/shirishpothi/Sorty/commit/\(BuildInfo.commit)")!) {
                        Text("Commit \(BuildInfo.shortCommit)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded {
                        HapticFeedbackManager.shared.tap()
                    })
                } else {
                    Text("Commit \(BuildInfo.shortCommit)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer().frame(height: 8)
            
            // Buttons
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
            
            Spacer().frame(height: 4)
            
            // Copyright
            Text("© 2026 Shirish Pothi")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(24)
        .frame(width: 300, height: 380)
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
