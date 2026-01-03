//
//  AboutView.swift
//  FileOrganizer
//
//  About dialog with liquid glass styling
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            // App Icon
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            
            // App Name
            Text("FileOrganiser")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            
            // Description
            Text("Intelligently organize your files with AI.\nLearn from your patterns and keep your workspace tidy.")
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
                    Link(destination: URL(string: "https://github.com/shirishpothi/FileOrganizer/commit/\(BuildInfo.commit)")!) {
                        Text("Commit \(BuildInfo.shortCommit)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
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
                    // Open HELP.md in browser or navigate to help section
                    if let url = URL(string: "https://github.com/shirishpothi/FileOrganizer#readme") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                
                Button("GitHub") {
                    if let url = URL(string: "https://github.com/shirishpothi/FileOrganizer") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
            
            Spacer().frame(height: 4)
            
            // Copyright
            Text("© 2024-2026 Shirish Pothi")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(24)
        .frame(width: 300, height: 380)
        .background(.ultraThinMaterial)
    }
}

#Preview {
    AboutView()
}
