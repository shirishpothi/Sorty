//
//  AboutView.swift
//  Sorty
//
//  About dialog with liquid glass styling
//

import AppKit
import SwiftUI

struct AboutView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let sponsorsURL = URL(string: "https://github.com/sponsors/shirishpothi")!
    private let docsURL = URL(string: "https://github.com/shirishpothi/Sorty#readme")!
    private let githubURL = URL(string: "https://github.com/shirishpothi/Sorty")!
    private var versionHistoryURL: URL {
        SparkleVersionHistoryLink.url(for: BuildInfo.version)
    }

    @State private var supportHovered = false
    @State private var docsHovered = false
    @State private var githubHovered = false
    @State private var accreditationsHovered = false
    @State private var versionHovered = false
    @State private var commitHovered = false
    let openAccreditations: (() -> Void)?

    init(openAccreditations: (() -> Void)? = nil) {
        self.openAccreditations = openAccreditations
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // App Icon
            AboutAppIconEasterEgg()
            
            // App Name
            Text("Sorty")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            
            // Description
            Text("Sorty: The FOSS File Organiser\nLearn from your patterns and keep your workspace tidy.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer().frame(height: 2)
            
            // Version Info - Centered
            VStack(spacing: 4) {
                Button {
                    HapticFeedbackManager.shared.tap()
                    NSWorkspace.shared.open(versionHistoryURL)
                } label: {
                    Text("Version \(BuildInfo.version)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("AboutVersionHistoryButton")
                .trackHoveredURL(versionHistoryURL)
                .scaleEffect(versionHovered ? 1.02 : 1.0)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) { versionHovered = hovering }
                    if hovering { HapticFeedbackManager.shared.selection() }
                }
                
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
            
            Spacer().frame(height: 4)
            
            // Buttons
            VStack(spacing: 10) {
                if FeatureFlags.supportDeveloperEnabled {
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
                }

                HStack(spacing: 10) {
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
            
            Spacer().frame(height: 6)

            Text("© 2026 Shirish Pothi")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.top, 2)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .frame(width: 420, height: 510)
        .modifier(AboutGlassBackground())
        .windowLinkHoverPillHost()
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }
}

// MARK: - About app icon easter egg

/// Tap the icon to flip through Sorty's build-channel icon variants. Auto-rotates
/// on its own (pausing while hovered, à la Ghostty's About window), and once you
/// manually cycle through every variant it bursts apart before settling back to
/// the running app icon.
private struct AboutAppIconEasterEgg: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var carousel = AboutIconCarousel()
    @State private var iconHovered = false

    private let iconSize: CGFloat = 128
    private let stageWidth: CGFloat = 176
    private let stageHeight: CGFloat = 148

    var body: some View {
        Button {
            carousel.handleTap(allowsBurst: !reduceMotion)
        } label: {
            ZStack {
                if carousel.isBursting && !reduceMotion {
                    IconBurst(startDate: carousel.burstStart)
                        .frame(width: 220, height: 220)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                SortyEnergyScanIcon(
                    image: carousel.currentImage,
                    size: iconSize,
                    cornerRadius: 22,
                    startDelay: 0.25,
                    sweepDuration: 2.2
                )
                .id(carousel.iconID)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                .scaleEffect(iconScale)
                .rotationEffect(.degrees(carousel.isBursting ? 12 : 0))
                .blur(radius: carousel.isBursting ? 6 : 0)
                .opacity(carousel.isBursting ? 0 : 1)
                .transition(.opacity)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: iconHovered)
            }
            .frame(width: stageWidth, height: stageHeight)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: carousel.iconID)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeIn(duration: 0.24), value: carousel.isBursting)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sorty app icon")
        .accessibilityHint("Click to cycle through icon variants")
        .accessibilityIdentifier("AboutAppIconButton")
        .onHover { hovering in
            iconHovered = hovering
            carousel.isHovering = hovering
            if hovering {
                HapticFeedbackManager.shared.selection()
            }
        }
        .onAppear { carousel.setAutoCycleEnabled(!reduceMotion) }
        .onChange(of: reduceMotion) { _, newValue in
            carousel.setAutoCycleEnabled(!newValue)
        }
        .onDisappear { carousel.stop() }
    }

    private var iconScale: CGFloat {
        if carousel.isBursting { return 0.08 }
        return iconHovered ? 1.05 : 1.0
    }
}

/// Drives the About-window icon carousel: holds the ordered variant images,
/// auto-rotates on a timer (paused while hovered), and triggers the burst.
@MainActor
private final class AboutIconCarousel: ObservableObject {
    @Published private(set) var index = 0
    @Published private(set) var iconID = 0
    @Published private(set) var isBursting = false
    @Published var isHovering = false

    private(set) var burstStart = Date()

    private let images: [NSImage]
    private let runningVariant: AboutAppIconVariant?
    private var manualTaps = 0
    private var cycleTask: Task<Void, Never>?
    private var burstTask: Task<Void, Never>?
    private var lastManualTapDate: Date?

    private let autoCycleInterval: Duration = .seconds(3)
    private let burstHoldInterval: Duration = .milliseconds(1700)
    private let manualPauseInterval: TimeInterval = 1.8

    init() {
        runningVariant = AboutAppIconVariant.current
        images = AboutAppIconVariant.cycleImages(current: runningVariant)
    }

    var currentImage: NSImage {
        images.indices.contains(index) ? images[index] : NSApplication.shared.applicationIconImage
    }

    /// Number of taps needed to trigger the burst: a full manual lap of the
    /// variants (typically three or four), with a sensible floor.
    private var tapsToBurst: Int {
        max(2, images.count)
    }

    func setAutoCycleEnabled(_ isEnabled: Bool) {
        guard isEnabled else {
            cycleTask?.cancel()
            cycleTask = nil
            return
        }

        guard cycleTask == nil else { return }
        cycleTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: self.autoCycleInterval)
                if Task.isCancelled { return }
                guard !self.isHovering, !self.isBursting, !self.isManualPauseActive else { continue }
                self.advance()
            }
        }
    }

    func stop() {
        cycleTask?.cancel()
        cycleTask = nil
        burstTask?.cancel()
        burstTask = nil
        reset()
    }

    func handleTap(allowsBurst: Bool) {
        guard !isBursting else { return }
        HapticFeedbackManager.shared.light()

        guard allowsBurst else {
            advance()
            return
        }

        manualTaps += 1
        lastManualTapDate = Date()
        if manualTaps >= tapsToBurst {
            triggerBurst()
        } else {
            advance()
        }
    }

    private func advance() {
        guard images.count > 1 else { return }
        index = (index + 1) % images.count
        iconID += 1
    }

    private func triggerBurst() {
        burstStart = Date()
        isBursting = true
        HapticFeedbackManager.shared.success()

        burstTask?.cancel()
        burstTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.burstHoldInterval ?? .seconds(1.7))
            guard let self, !Task.isCancelled else { return }
            self.reset()
        }
    }

    private func reset() {
        index = 0
        iconID += 1
        manualTaps = 0
        isBursting = false
    }

    private var isManualPauseActive: Bool {
        guard let lastManualTapDate else { return false }
        return Date().timeIntervalSince(lastManualTapDate) < manualPauseInterval
    }
}

private enum AboutAppIconVariant: String, CaseIterable {
    case debug = "Debug"
    case release = "Release"

    /// Build channel recorded by scripts/build.sh in Info.plist (SortyBuildVariant).
    /// Nil for plain Xcode/SPM runs that don't go through the packaging script.
    static var current: AboutAppIconVariant? {
        let candidates = [
            Bundle.main.infoDictionary?["SortyBuildVariant"] as? String,
            Bundle.main.infoDictionary?["APP_ICON_VARIANT"] as? String,
            ProcessInfo.processInfo.environment["APP_ICON_VARIANT"],
            ProcessInfo.processInfo.environment["SORTY_BUILD_VARIANT"]
        ]

        for candidate in candidates {
            if let variant = variant(from: candidate) {
                return variant
            }
        }

        if let iconFile = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String,
           let variant = variant(from: iconFile) {
            return variant
        }

        return nil
    }

    /// Slot 0 is always the running app icon; the remaining slots are the other
    /// variants, excluding the one this build already ships so nothing duplicates.
    static func cycleImages(current: AboutAppIconVariant?) -> [NSImage] {
        let appIcon = AboutIconImageNormalizer.normalized(
            NSApplication.shared.applicationIconImage,
            opticalScale: current?.opticalScale ?? 1
        )

        let others = allCases.filter { variant in
            guard let current else { return true }
            return variant != current
        }

        var images: [NSImage] = [appIcon]
        images.append(contentsOf: others.compactMap { variant in
            loadImage(for: variant).map {
                AboutIconImageNormalizer.normalized($0, opticalScale: variant.opticalScale)
            }
        })
        return images
    }

    private var opticalScale: CGFloat {
        1
    }

    private static func variant(from rawValue: String?) -> AboutAppIconVariant? {
        guard let rawValue else { return nil }
        let normalized = rawValue
            .replacingOccurrences(of: "AppIcon-", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".icns", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".png", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "debug", "dev", "local", "ci", "blacksmith":
            return .debug
        case "release", "prod", "production":
            return .release
        default:
            return nil
        }
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
        let fileName = "AppIcon-\(variant.rawValue).png"
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let roots = [SortyResources.bundle.resourceURL, Bundle.main.resourceURL].compactMap { $0 }

        var urls: [URL] = []
        for root in roots {
            urls.append(root.appendingPathComponent("AppIcons/\(fileName)"))
            urls.append(root.appendingPathComponent(fileName))
            urls.append(root.appendingPathComponent("Sorty_SortyLib.bundle/AppIcons/\(fileName)"))
            urls.append(root.appendingPathComponent("SortyLib_SortyLib.bundle/AppIcons/\(fileName)"))
        }
        urls.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/AppIcons/\(fileName)"))
        urls.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Sorty_SortyLib.bundle/AppIcons/\(fileName)"))
        urls.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/SortyLib_SortyLib.bundle/AppIcons/\(fileName)"))
        // Development fallbacks (running directly from the source tree).
        urls.append(cwd.appendingPathComponent("Sources/SortyLib/Resources/AppIcons/\(fileName)"))
        urls.append(cwd.appendingPathComponent("Assets/AppIcon/\(fileName)"))

        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }
}

private enum AboutIconImageNormalizer {
    /// Ignore soft source-image shadows when measuring each icon's visual size.
    /// The carousel adds one consistent shadow after normalization.
    private static let artworkAlphaThreshold: CGFloat = 0.5

    static func normalized(_ image: NSImage, opticalScale: CGFloat) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let visibleBounds = visibleBounds(in: cgImage),
              let croppedImage = cgImage.cropping(to: visibleBounds) else {
            return image
        }

        let canvasSize = NSSize(width: 512, height: 512)
        let output = NSImage(size: canvasSize)
        output.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()

        let croppedSize = CGSize(width: CGFloat(croppedImage.width), height: CGFloat(croppedImage.height))
        let scale = min(canvasSize.width / croppedSize.width, canvasSize.height / croppedSize.height)
            * opticalScale
        let drawSize = NSSize(width: croppedSize.width * scale, height: croppedSize.height * scale)
        let drawRect = NSRect(
            x: (canvasSize.width - drawSize.width) / 2,
            y: (canvasSize.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )

        NSImage(cgImage: croppedImage, size: croppedSize).draw(in: drawRect)
        output.unlockFocus()
        output.size = canvasSize
        return output
    }

    private static func visibleBounds(in image: CGImage) -> CGRect? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width where
                (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) >= artworkAlphaThreshold
            {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return nil
        }

        return CGRect(
            x: CGFloat(minX),
            y: CGFloat(minY),
            width: CGFloat(maxX - minX + 1),
            height: CGFloat(maxY - minY + 1)
        )
    }
}

// MARK: - Icon burst

/// A physics-driven particle burst: a radial spray of shards and sparks that
/// decelerate, fall under gravity, shrink, and fade, fronted by a quick flash ring.
private struct IconBurst: View {
    let startDate: Date

    private let particles = IconBurst.makeParticles()

    var body: some View {
        SwiftUI.TimelineView(.animation) { context in
            Canvas { ctx, size in
                let t = max(0, context.date.timeIntervalSince(startDate))
                let center = CGPoint(x: size.width / 2, y: size.height / 2)

                // Flash ring
                let ringDuration = 0.42
                let ringT = min(1, t / ringDuration)
                if ringT < 1 {
                    let radius = 16 + ringT * 78
                    let alpha = pow(1 - ringT, 1.5) * 0.85
                    let rect = CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    ctx.stroke(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(alpha)),
                        lineWidth: 3.5 * (1 - ringT) + 0.5
                    )
                }

                for p in particles where t < p.lifetime {
                    let progress = t / p.lifetime
                    // Decelerating outward travel (ease-out) plus gravity.
                    let travel = (1 - exp(-3.4 * t)) / 3.4
                    let dx = p.velocity.dx * travel
                    let dy = p.velocity.dy * travel + 0.5 * 560 * t * t
                    let pos = CGPoint(x: center.x + dx, y: center.y + dy)

                    let alpha = pow(1 - progress, 1.4)
                    let psize = p.size * (1 - progress * 0.55)
                    let rect = CGRect(
                        x: pos.x - psize / 2,
                        y: pos.y - psize / 2,
                        width: psize,
                        height: max(0.5, psize)
                    )
                    let shape = p.isSpark
                        ? Path(roundedRect: rect, cornerRadius: psize / 2)
                        : Path(ellipseIn: rect)
                    ctx.fill(shape, with: .color(p.color.opacity(alpha)))
                }
            }
        }
    }

    private static func makeParticles() -> [BurstParticle] {
        var rng = SystemRandomNumberGenerator()
        let palette: [Color] = [.teal, .blue, .purple, .pink, .orange, .white]
        let count = 44

        return (0..<count).map { i in
            let jitter = Double.random(in: -0.16...0.16, using: &rng)
            let angle = (Double(i) / Double(count)) * .pi * 2 + jitter
            let speed = Double.random(in: 150...360, using: &rng)
            return BurstParticle(
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                size: CGFloat.random(in: 4...11, using: &rng),
                color: palette[i % palette.count],
                lifetime: Double.random(in: 0.7...1.15, using: &rng),
                isSpark: i % 5 == 0
            )
        }
    }
}

private struct BurstParticle: Identifiable {
    let id = UUID()
    let velocity: CGVector
    let size: CGFloat
    let color: Color
    let lifetime: Double
    let isSpark: Bool
}

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
