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
    let openAccreditations: (() -> Void)?

    init(openAccreditations: (() -> Void)? = nil) {
        self.openAccreditations = openAccreditations
    }
    
    var body: some View {
        VStack(spacing: 15) {
            // App Icon
            AboutAppIconEasterEgg()
            
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
            
            Spacer().frame(height: 6)
            
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
                .buttonStyle(.sortyProminent)
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
                    .buttonStyle(.sortyBordered)
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
                    .buttonStyle(.sortyBordered)
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
                .buttonStyle(.sortyBordered)
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
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.top, 2)
        }
        .padding(.horizontal, 30)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(width: 430, height: 540)
        .modifier(AboutGlassBackground())
        .windowLinkHoverPillHost()
    }
}

private struct AboutAppIconEasterEgg: View {
    @State private var iconHovered = false
    @State private var selectedIconIndex = 0
    @State private var clickCount = 0
    @State private var isBursting = false
    @State private var burstID = UUID()

    private let iconSize: CGFloat = 128

    private var icons: [NSImage] {
        AboutAppIconVariant.cycleImages()
    }

    private var currentImage: NSImage {
        icons.indices.contains(selectedIconIndex)
            ? icons[selectedIconIndex]
            : NSApplication.shared.applicationIconImage
    }

    var body: some View {
        Button {
            handleClick()
        } label: {
            ZStack {
                if isBursting {
                    IconBurstParticles(burstID: burstID)
                        .frame(width: 160, height: 160)
                        .transition(.opacity)
                }

                Image(nsImage: currentImage)
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    .scaleEffect(isBursting ? 0.18 : (iconHovered ? 1.05 : 1.0))
                    .rotationEffect(.degrees(isBursting ? 18 : 0))
                    .opacity(isBursting ? 0 : 1)
            }
            .frame(width: 176, height: 148)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sorty app icon")
        .accessibilityIdentifier("AboutAppIconButton")
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                iconHovered = hovering
            }
            if hovering {
                HapticFeedbackManager.shared.selection()
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.68), value: selectedIconIndex)
        .animation(.spring(response: 0.36, dampingFraction: 0.62), value: isBursting)
    }

    private func handleClick() {
        guard !isBursting else { return }
        HapticFeedbackManager.shared.light()

        clickCount += 1
        switch clickCount {
        case 1:
            selectedIconIndex = min(1, icons.count - 1)
        case 2:
            selectedIconIndex = min(2, icons.count - 1)
        case 3:
            selectedIconIndex = 0
        default:
            burstID = UUID()
            isBursting = true
            HapticFeedbackManager.shared.success()

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                selectedIconIndex = 0
                clickCount = 0
                isBursting = false
            }
        }
    }
}

private enum AboutAppIconVariant: String, CaseIterable {
    case debug = "Debug"
    case release = "Release"
    case ci = "CI"

    #if DEBUG
    private static let current: AboutAppIconVariant = .debug
    #else
    private static let current: AboutAppIconVariant = .release
    #endif

    static func cycleImages() -> [NSImage] {
        let orderedVariants = [current] + allCases.filter { $0 != current }
        var images = orderedVariants.compactMap { loadImage(for: $0) }
        if images.isEmpty {
            images = [NSApplication.shared.applicationIconImage]
        } else {
            images[0] = NSApplication.shared.applicationIconImage
        }
        return images
    }

    private static func loadImage(for variant: AboutAppIconVariant) -> NSImage? {
        for url in candidateURLs(for: variant) where FileManager.default.fileExists(atPath: url.path) {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }

    private static func candidateURLs(for variant: AboutAppIconVariant) -> [URL] {
        let fileName = "AppIcon-\(variant.rawValue).icns"
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        var urls: [URL] = []

        for root in [Bundle.main.resourceURL, Bundle.module.resourceURL].compactMap({ $0 }) {
            urls.append(root.appendingPathComponent(fileName))
            urls.append(root.appendingPathComponent("AppIcons/\(fileName)"))
            urls.append(root.appendingPathComponent("SortyLib_SortyLib.bundle/AppIcons/\(fileName)"))
        }

        urls.append(cwd.appendingPathComponent("Assets/AppIcon/\(fileName)"))
        return urls
    }
}

private struct IconBurstParticles: View {
    let burstID: UUID

    private let particles: [IconBurstParticle] = (0..<18).map { index in
        let angle = Double(index) / 18.0 * .pi * 2
        return IconBurstParticle(
            angle: angle,
            distance: CGFloat(46 + (index % 4) * 14),
            size: CGFloat(5 + (index % 3) * 3),
            color: [.teal, .blue, .purple, SortyDesignSystem.Colors.resolvedAccent, .orange][index % 5]
        )
    }

    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                IconBurstParticleView(particle: particle, burstID: burstID)
            }
        }
    }
}

private struct IconBurstParticle: Identifiable {
    let id = UUID()
    let angle: Double
    let distance: CGFloat
    let size: CGFloat
    let color: Color
}

private struct IconBurstParticleView: View {
    let particle: IconBurstParticle
    let burstID: UUID
    @State private var expanded = false

    var body: some View {
        Circle()
            .fill(particle.color)
            .frame(width: particle.size, height: particle.size)
            .offset(
                x: expanded ? CGFloat(cos(particle.angle)) * particle.distance : 0,
                y: expanded ? CGFloat(sin(particle.angle)) * particle.distance : 0
            )
            .scaleEffect(expanded ? 0.2 : 1.0)
            .opacity(expanded ? 0 : 1)
            .onAppear {
                expanded = false
                withAnimation(.easeOut(duration: 0.72)) {
                    expanded = true
                }
            }
            .onChange(of: burstID) { _, _ in
                expanded = false
                withAnimation(.easeOut(duration: 0.72)) {
                    expanded = true
                }
            }
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
