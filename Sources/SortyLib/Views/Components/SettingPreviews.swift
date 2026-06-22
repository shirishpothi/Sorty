//
//  SettingPreviews.swift
//  Sorty
//
//  Live preview components for non-obvious settings.
//  They show what a control will actually do without needing to run a scan.
//

import SwiftUI
import AppKit

// MARK: - Shared container

struct SettingPreviewPanel<Content: View>: View {
    let title: String?
    let icon: String?
    let accent: Color
    @ViewBuilder let content: Content

    init(
        title: String? = nil,
        icon: String? = nil,
        accent: Color = .accentColor,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                HStack(spacing: 4) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.caption2)
                            .foregroundStyle(accent)
                    }
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }
            content
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(accent.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(accent.opacity(0.18), lineWidth: 1)
                )
        }
    }
}

struct SettingPreviewRow: View {
    let label: String
    let value: String
    let valueColor: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - 1. AI Vision preview

struct VisionTogglePreview: View {
    let isEnabled: Bool
    let supportsVision: Bool

    private let withVision = "2026-03-12 Checkout Error Screenshot.png"
    private let withoutVision = "IMG_4827.png"
    private let altWithoutVision = "Screen Shot 2026-03-12 at 4.17.52 PM.png"

    var body: some View {
        SettingPreviewPanel(
            title: "Vision Preview",
            icon: "eye",
            accent: .teal
        ) {
            if !supportsVision {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("This model doesn't support vision. Filenames stay as-is.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    SettingPreviewRow(
                        label: "With Vision",
                        value: withVision,
                        valueColor: .teal,
                        icon: isEnabled ? "checkmark.circle.fill" : "circle"
                    )
                    SettingPreviewRow(
                        label: "Without Vision",
                        value: isEnabled ? altWithoutVision : withoutVision,
                        valueColor: .secondary,
                        icon: isEnabled ? "circle" : "checkmark.circle.fill"
                    )
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isEnabled)
    }
}

// MARK: - 2. Fast Mode / Deep Scan preview

struct FastModeTogglePreview: View {
    let isFastModeOn: Bool
    let namingOptions: RenameNamingOptions

    private let deepScanName = "Acme_MSA_Final_Executed.pdf"
    private let fastModeName = "scan_2026_03_19.pdf"

    private func normalize(_ name: String) -> String {
        FilenameNormalizer.normalize(name, originalFilename: "scan_001.pdf", options: namingOptions) ?? name
    }

    private var estimatedTimeFast: String { "≈ 5s" }
    private var estimatedTimeDeep: String { "≈ 25s" }

    var body: some View {
        SettingPreviewPanel(
            title: "Scan Preview",
            icon: "doc.text.magnifyingglass",
            accent: .blue
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Deep Scan")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isFastModeOn ? Color.secondary : Color.blue)
                        Text(normalize(deepScanName))
                            .font(.caption.monospaced())
                            .foregroundStyle(isFastModeOn ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().frame(height: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Fast Mode")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isFastModeOn ? .blue : .secondary)
                        Text(normalize(fastModeName))
                            .font(.caption.monospaced())
                            .foregroundStyle(isFastModeOn ? .primary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(isFastModeOn ? "Estimated for 100 files: \(estimatedTimeFast)" : "Estimated for 100 files: \(estimatedTimeDeep)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isFastModeOn)
    }
}

// MARK: - 3. Temperature preview (Focused vs Creative folder trees)

struct TemperaturePreview: View {
    let temperature: Double

    private var label: String {
        if temperature <= 0.2 { return "Focused" }
        if temperature <= 0.5 { return "Balanced" }
        if temperature <= 0.8 { return "Varied" }
        return "Creative"
    }

    private var accent: Color {
        if temperature <= 0.2 { return .blue }
        if temperature <= 0.5 { return .green }
        if temperature <= 0.8 { return .orange }
        return .purple
    }

    private var sampleTree: [String] {
        if temperature <= 0.2 {
            return [
                "Documents",
                "  2026",
                "    Invoices",
                "      2026-03-19 Acme Invoice.pdf"
            ]
        }
        if temperature <= 0.5 {
            return [
                "Documents",
                "  Invoices",
                "    2026-Q1",
                "      2026-03-19 Acme Invoice.pdf"
            ]
        }
        if temperature <= 0.8 {
            return [
                "Money",
                "  2026 Q1",
                "    Vendor Acme",
                "      2026-03-19 Acme Invoice Final.pdf"
            ]
        }
        return [
            "Q1-Paperwork",
            "  Vendor-Stack",
            "    Acme",
            "      2026-March-Acme-MSA-Final-Executed.pdf"
        ]
    }

    var body: some View {
        SettingPreviewPanel(
            title: "Output Preview",
            icon: "folder.tree",
            accent: accent
        ) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(accent).frame(width: 6, height: 6)
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                    Spacer()
                    Text(String(format: "%.2f", temperature))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(sampleTree.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .foregroundStyle(leadingTextColor(for: line))
                            .lineLimit(1)
                    }
                }
                .padding(.top, 2)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: temperature)
    }

    private func leadingTextColor(for line: String) -> Color {
        let depth = line.prefix { $0 == " " }.count / 2
        switch depth {
        case 0: return .primary
        case 1: return .secondary
        case 2: return .secondary.opacity(0.85)
        default: return .secondary.opacity(0.7)
        }
    }
}

// MARK: - 4. Max Top-Level Folders mock tree

struct MaxFoldersPreview: View {
    let maxFolders: Int

    private let minimalTree = [
        ("📁 Documents", "200 files"),
        ("📁 Photos", "340 files"),
        ("📁 Other", "60 files")
    ]

    private let mediumTree: [(String, String)] = [
        ("📁 2026-Q1-Invoices", "55 files"),
        ("📁 2026-Q2-Invoices", "40 files"),
        ("📁 Personal-Docs", "120 files"),
        ("📁 Photos", "340 files"),
        ("📁 Receipts", "85 files"),
        ("📁 Tax-2025", "32 files"),
        ("📁 Work-Proposals", "18 files"),
        ("📁 Screenshots", "210 files"),
        ("📁 Downloads-Old", "95 files"),
        ("📁 Other", "60 files")
    ]

    private let detailedTree: [(String, String)] = [
        ("📁 2025-Receipts", "28 files"),
        ("📁 2026-Q1-Invoices", "55 files"),
        ("📁 2026-Q2-Invoices", "40 files"),
        ("📁 2026-Contracts", "12 files"),
        ("📁 Personal-Letters", "8 files"),
        ("📁 Personal-Tax", "16 files"),
        ("📁 Photos-2025", "180 files"),
        ("📁 Photos-2026", "160 files"),
        ("📁 Receipts-Amazon", "32 files"),
        ("📁 Receipts-Apple", "20 files"),
        ("📁 Screenshots-App", "120 files"),
        ("📁 Screenshots-Web", "90 files"),
        ("📁 Tax-2024", "24 files"),
        ("📁 Tax-2025", "32 files"),
        ("📁 Work-Proposals", "18 files"),
        ("📁 Work-Client-Acme", "14 files"),
        ("📁 Downloads-Old", "95 files"),
        ("📁 Voice-Memos", "26 files"),
        ("📁 Notes-Work", "44 files"),
        ("📁 Other", "60 files")
    ]

    private var displayTree: [(String, String)] {
        if maxFolders <= 4 { return Array(minimalTree.prefix(maxFolders)) }
        if maxFolders <= 11 { return Array(mediumTree.prefix(min(maxFolders, mediumTree.count))) }
        return Array(detailedTree.prefix(min(maxFolders, detailedTree.count)))
    }

    var body: some View {
        SettingPreviewPanel(
            title: "Top-Level Preview",
            icon: "folder",
            accent: .purple
        ) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(displayTree.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        Text(item.0)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(item.1)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: maxFolders)
    }
}

// MARK: - 5. Naming preset preview

struct NamingPresetPreview: View {
    let presetId: UUID?
    let namingStyle: NamingStyle
    let namingOptions: RenameNamingOptions

    private let inputSamples: [String] = [
        "scan_001.pdf",
        "IMG_4827.png",
        "Microsoft Word - Acme MSA Final.docx"
    ]

    private func examples(for style: NamingStyle) -> [String] {
        switch style {
        case .descriptive:
            return [
                "2026-03-19 Acme MSA Agreement.pdf",
                "2026-03-12 Checkout Error Screenshot.png",
                "2026-03-19 Acme MSA Final Agreement.docx"
            ]
        case .minimalist:
            return [
                "Acme MSA Agreement.pdf",
                "Checkout Error Screenshot.png",
                "Acme MSA Agreement.docx"
            ]
        case .technical:
            return [
                "AGREEMENT_20260319_ACME_1843.pdf",
                "SCREENSHOT_20260312_162045.png",
                "AGREEMENT_20260319_ACME_1843.docx"
            ]
        case .datePrefix:
            return [
                "2026-03-19 - Acme - MSA Agreement.pdf",
                "2026-03-12 - Screenshot - Checkout Error.png",
                "2026-03-19 - Acme - MSA Agreement.docx"
            ]
        case .screenshotFriendly:
            return [
                "2026-03-19 MSA Agreement Screenshot.png",
                "2026-03-12 Checkout Error Screenshot.png",
                "2026-03-19 Acme MSA Agreement Screenshot.docx"
            ]
        case .custom:
            return []
        }
    }

    private var resolvedStyle: NamingStyle {
        guard let presetId, let style = NamingPresetManager.shared.namingStyle(for: presetId) else {
            return namingStyle
        }
        return style
    }

    private var displayExamples: [String] {
        if resolvedStyle == .custom { return [] }
        return examples(for: resolvedStyle)
    }

    private var fallback: [String] {
        inputSamples.map { original in
            FilenameNormalizer.normalize(original, originalFilename: original, options: namingOptions) ?? original
        }
    }

    var body: some View {
        SettingPreviewPanel(
            title: "Preset Examples",
            icon: "doc.text",
            accent: .indigo
        ) {
            if displayExamples.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom preset — define your own instructions below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(fallback.enumerated()), id: \.offset) { _, name in
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(name)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(zip(inputSamples, displayExamples).enumerated()), id: \.offset) { _, pair in
                        HStack(spacing: 6) {
                            Text(pair.0)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.indigo)
                            Text(pair.1)
                                .font(.caption.monospaced())
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: presetId)
    }
}

// MARK: - 6. Date policy + language preview

struct DatePolicyPreview: View {
    let datePolicy: RenameDatePolicy
    let language: String

    private let inputName = "Acme_Invoice_032026.pdf"

    private func transformed(for policy: RenameDatePolicy) -> String {
        switch policy {
        case .never:
            return "Acme Invoice March 2026.pdf"
        case .whenFound:
            return "Acme Invoice 03-2026.pdf"
        case .alwaysWhenReliable:
            return "2026-03-19 Acme Invoice.pdf"
        }
    }

    private func localizedSample(_ language: String) -> String {
        let lang = language.lowercased()
        if lang.contains("spanish") || lang.contains("español") || lang.contains("es") {
            return "Recibo Acme 2026-03-19.pdf"
        }
        if lang.contains("french") || lang.contains("français") || lang.contains("fr") {
            return "Reçu Acme 2026-03-19.pdf"
        }
        if lang.contains("german") || lang.contains("deutsch") || lang.contains("de") {
            return "Rechnung Acme 2026-03-19.pdf"
        }
        if lang.contains("japanese") || lang.contains("日本語") || lang.contains("ja") {
            return "請求書 Acme 2026-03-19.pdf"
        }
        if lang.isEmpty || lang == "english" {
            return "Acme Invoice 2026-03-19.pdf"
        }
        return "Acme Invoice 2026-03-19.pdf"
    }

    var body: some View {
        SettingPreviewPanel(
            title: "Date & Language Preview",
            icon: "calendar",
            accent: .orange
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Date →")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(transformed(for: datePolicy))
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contentTransition(.opacity)
                }

                HStack(spacing: 6) {
                    Text("Language →")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(localizedSample(language))
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: datePolicy)
        .animation(.easeInOut(duration: 0.18), value: language)
    }
}

// MARK: - 7. Privacy toggle previews

struct PrivacyTogglePreview: View {
    let isEnabled: Bool

    private let realUsername = "shirish"
    private let realPath = "/Users/shirish/Documents/Acme_Invoice.pdf"

    private var maskedUsername: String { "█████████" }
    private var maskedPath: String { "/Users/█████████/Documents/Acme_Invoice.pdf" }

    var body: some View {
        SettingPreviewPanel(
            title: "Privacy Preview",
            icon: "lock.shield",
            accent: .green
        ) {
            VStack(alignment: .leading, spacing: 6) {
                SettingPreviewRow(
                    label: "Username",
                    value: isEnabled ? maskedUsername : realUsername,
                    valueColor: isEnabled ? .secondary : .primary,
                    icon: isEnabled ? "eye.slash" : "person"
                )
                SettingPreviewRow(
                    label: "Path",
                    value: isEnabled ? maskedPath : realPath,
                    valueColor: isEnabled ? .secondary : .primary,
                    icon: isEnabled ? "eye.slash" : "folder"
                )
                SettingPreviewRow(
                    label: "API Key",
                    value: isEnabled ? "sk-████████████████████" : "sk-Abc12...Xy9z",
                    valueColor: isEnabled ? .secondary : .primary,
                    icon: isEnabled ? "eye.slash" : "key"
                )
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isEnabled)
    }
}

struct InternetPrivacyPreview: View {
    let isEnabled: Bool

    var body: some View {
        SettingPreviewPanel(
            title: "Network Preview",
            icon: "network",
            accent: .green
        ) {
            VStack(alignment: .leading, spacing: 6) {
                SettingPreviewRow(
                    label: "POST",
                    value: isEnabled ? "Blocked (localhost only)" : "https://api.openai.com/v1/chat/completions",
                    valueColor: isEnabled ? .red : .primary,
                    icon: isEnabled ? "xmark.shield" : "globe"
                )
                SettingPreviewRow(
                    label: "GET",
                    value: isEnabled ? "http://localhost:11434/v1/models" : "https://api.anthropic.com/v1/messages",
                    valueColor: isEnabled ? .green : .primary,
                    icon: isEnabled ? "checkmark.shield" : "globe"
                )
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isEnabled)
    }
}

// MARK: - 8. Workspace Health threshold preview

struct WorkspaceHealthThresholdPreview: View {
    let config: WorkspaceHealthConfig

    private struct SampleFile {
        let name: String
        let size: Int64
        let daysOld: Int
        let isScreenshot: Bool
        let isInDownloads: Bool
        let isUnorganized: Bool
    }

    private let samples: [SampleFile] = [
        SampleFile(name: "big-video.mp4", size: 2_147_483_648, daysOld: 30, isScreenshot: false, isInDownloads: false, isUnorganized: false),
        SampleFile(name: "installer.dmg", size: 1_400_000_000, daysOld: 14, isScreenshot: false, isInDownloads: true, isUnorganized: true),
        SampleFile(name: "archive.zip", size: 671_088_640, daysOld: 200, isScreenshot: false, isInDownloads: true, isUnorganized: false),
        SampleFile(name: "Screen Shot 2025-01-12 at 4.17.52 PM.png", size: 524_288, daysOld: 90, isScreenshot: true, isInDownloads: false, isUnorganized: false),
        SampleFile(name: "Screen Shot 2025-01-13 at 9.02.11 AM.png", size: 480_000, daysOld: 89, isScreenshot: true, isInDownloads: false, isUnorganized: false),
        SampleFile(name: "Screen Shot 2025-01-14 at 1.45.22 PM.png", size: 510_000, daysOld: 88, isScreenshot: true, isInDownloads: false, isUnorganized: false),
        SampleFile(name: "Screen Shot 2025-01-15 at 2.11.50 PM.png", size: 502_000, daysOld: 87, isScreenshot: true, isInDownloads: false, isUnorganized: false),
        SampleFile(name: "Screen Shot 2025-01-16 at 8.20.01 AM.png", size: 480_000, daysOld: 86, isScreenshot: true, isInDownloads: false, isUnorganized: false),
        SampleFile(name: "Screen Shot 2025-01-17 at 7.00.13 PM.png", size: 480_000, daysOld: 85, isScreenshot: true, isInDownloads: false, isUnorganized: false),
        SampleFile(name: "Screen Shot 2025-01-18 at 3.32.45 PM.png", size: 480_000, daysOld: 84, isScreenshot: true, isInDownloads: false, isUnorganized: false),
        SampleFile(name: "Screen Shot 2025-01-19 at 5.55.30 PM.png", size: 480_000, daysOld: 83, isScreenshot: true, isInDownloads: false, isUnorganized: false),
        SampleFile(name: "Screen Shot 2025-01-20 at 11.00.00 AM.png", size: 480_000, daysOld: 82, isScreenshot: true, isInDownloads: false, isUnorganized: false),
        SampleFile(name: "Screen Shot 2025-01-21 at 4.30.00 PM.png", size: 480_000, daysOld: 81, isScreenshot: true, isInDownloads: false, isUnorganized: false),
        SampleFile(name: "Screen Shot 2025-01-22 at 9.45.00 AM.png", size: 480_000, daysOld: 80, isScreenshot: true, isInDownloads: false, isUnorganized: false),
        SampleFile(name: "Screen Shot 2025-01-23 at 2.10.00 PM.png", size: 480_000, daysOld: 79, isScreenshot: true, isInDownloads: false, isUnorganized: false),
        SampleFile(name: "old-doc-2022.docx", size: 32_000, daysOld: 1400, isScreenshot: false, isInDownloads: false, isUnorganized: false),
        SampleFile(name: "old-budget.xlsx", size: 48_000, daysOld: 800, isScreenshot: false, isInDownloads: false, isUnorganized: false),
        SampleFile(name: "old-photos.zip", size: 320_000_000, daysOld: 500, isScreenshot: false, isInDownloads: false, isUnorganized: false),
        SampleFile(name: "loose-doc.txt", size: 8_000, daysOld: 5, isScreenshot: false, isInDownloads: false, isUnorganized: true),
        SampleFile(name: "random.mov", size: 240_000_000, daysOld: 12, isScreenshot: false, isInDownloads: true, isUnorganized: true)
    ]

    private var largeFlagged: [SampleFile] {
        samples.filter { $0.size > config.largeFileSizeThreshold }
    }

    private var oldFlagged: [SampleFile] {
        let threshold = config.oldFileThreshold
        return samples.filter {
            Double($0.daysOld) * 86400 > threshold && !($0.size > config.largeFileSizeThreshold)
        }
    }

    private var oldCount: Int { oldFlagged.count }

    private var downloadFlagged: [SampleFile] {
        let threshold = config.downloadClutterThreshold
        return samples.filter {
            $0.isInDownloads && Double($0.daysOld) * 86400 > threshold
        }
    }

    private var screenshotFlagged: [SampleFile] {
        let screenshots = samples.filter { $0.isScreenshot }
        return screenshots.count >= config.minScreenshotCount ? Array(screenshots.prefix(3)) : []
    }

    private var unorganizedFlagged: [SampleFile] {
        samples.filter { $0.isUnorganized }
    }

    var body: some View {
        SettingPreviewPanel(
            title: "Sample Flagged Files",
            icon: "flag.checkered",
            accent: .mint
        ) {
            VStack(alignment: .leading, spacing: 6) {
                flaggedRow(
                    title: "Large files",
                    count: largeFlagged.count,
                    total: samples.count,
                    examples: largeFlagged.prefix(3).map { format($0) }
                )
                flaggedRow(
                    title: "Old files",
                    count: oldCount,
                    total: samples.count,
                    examples: oldFlagged.prefix(3).map { "\($0.name) (\($0.daysOld) days)" }
                )
                flaggedRow(
                    title: "Download clutter",
                    count: downloadFlagged.count,
                    total: samples.count,
                    examples: downloadFlagged.prefix(3).map { $0.name }
                )
                flaggedRow(
                    title: "Screenshot collection (\(samples.filter { $0.isScreenshot }.count) found)",
                    count: screenshotFlagged.count,
                    total: config.minScreenshotCount,
                    examples: screenshotFlagged.prefix(2).map { $0.name }
                )
                flaggedRow(
                    title: "Unorganized (min \(config.minUnorganizedCount))",
                    count: unorganizedFlagged.count,
                    total: config.minUnorganizedCount,
                    examples: unorganizedFlagged.prefix(3).map { $0.name }
                )
            }
        }
        .animation(.easeInOut(duration: 0.18), value: config)
    }

    private func format(_ file: SampleFile) -> String {
        let size = ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
        return "\(file.name) (\(size))"
    }

    @ViewBuilder
    private func flaggedRow(title: String, count: Int, total: Int, examples: [String]) -> some View {
        let active = count > 0 && count >= total
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: active ? "flag.fill" : "flag")
                    .font(.caption2)
                    .foregroundStyle(active ? .mint : .secondary)
                Text(title)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(count) of \(samples.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(active ? .mint : .secondary)
            }
            if active, !examples.isEmpty {
                Text(examples.joined(separator: ", "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
    }
}

// MARK: - 9. Timeout persona + progress

struct TimeoutPersonaPreview: View {
    let value: TimeInterval
    let isRequest: Bool

    private struct Persona {
        let label: String
        let range: ClosedRange<TimeInterval>
        let description: String
    }

    private var personas: [Persona] {
        if isRequest {
            return [
                Persona(label: "Local", range: 30...60, description: "Ollama, local servers, offline workflows"),
                Persona(label: "Standard", range: 60...180, description: "OpenAI, Anthropic, Gemini — typical"),
                Persona(label: "Patient", range: 180...600, description: "Long context, complex reasoning"),
                Persona(label: "Extensive", range: 600...1800, description: "Large scans, exhaustive analysis")
            ]
        } else {
            return [
                Persona(label: "Quick", range: 60...120, description: "Most Sorty runs finish in 15-45s"),
                Persona(label: "Standard", range: 120...600, description: "Typical organization runs"),
                Persona(label: "Patient", range: 600...1800, description: "Large folders, deep scans")
            ]
        }
    }

    private var matchedPersona: Persona {
        personas.first { $0.range.contains(value) } ?? personas.last!
    }

    private var barProgress: Double {
        let maxValue: Double = isRequest ? 1800 : 1800
        return min(1.0, value / maxValue)
    }

    var body: some View {
        SettingPreviewPanel(
            title: "Timeout Profile",
            icon: "clock",
            accent: .orange
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(matchedPersona.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Spacer()
                    Text("\(Int(value))s")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(matchedPersona.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.secondary.opacity(0.18))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.orange.opacity(0.7))
                            .frame(width: max(4, geo.size.width * barProgress))
                            .animation(.easeInOut(duration: 0.2), value: barProgress)
                    }
                }
                .frame(height: 6)

                Text("Tip: most Sorty runs finish in 15-45s.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: value)
    }
}

// MARK: - 10. Duplicate detection threshold preview

struct DuplicateThresholdPreview: View {
    let minSizeMB: Double
    let semanticThreshold: Double

    private struct SampleImage {
        let name: String
        let size: Int64
        let match: Double
    }

    private let samples: [SampleImage] = [
        SampleImage(name: "vacation-beach-1.jpg", size: 4_500_000, match: 0.98),
        SampleImage(name: "vacation-beach-1-compressed.jpg", size: 1_200_000, match: 0.94),
        SampleImage(name: "vacation-beach-1-cropped.jpg", size: 980_000, match: 0.88),
        SampleImage(name: "vacation-beach-1-thumb.jpg", size: 80_000, match: 0.82),
        SampleImage(name: "mountain-sunset.jpg", size: 3_200_000, match: 0.45)
    ]

    private var filteredBySize: [SampleImage] {
        let minBytes = Int64(minSizeMB * 1024 * 1024)
        return samples.filter { $0.size >= minBytes }
    }

    private var matchingBySemantic: [SampleImage] {
        filteredBySize.filter { $0.match >= semanticThreshold }
    }

    private func formatSize(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var body: some View {
        SettingPreviewPanel(
            title: "Duplicate Candidates",
            icon: "doc.on.doc",
            accent: .purple
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Size filter")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text("\(filteredBySize.count) of \(samples.count) files")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Semantic match ≥ \(Int((semanticThreshold * 100).rounded()))%")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text("\(matchingBySemantic.count) matches")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(matchingBySemantic.isEmpty ? Color.secondary : Color.purple)
                }

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                        let sizeOK = sample.size >= Int64(minSizeMB * 1024 * 1024)
                        let matchOK = sample.match >= semanticThreshold
                        let dimmed = !sizeOK
                        HStack(spacing: 6) {
                            Image(systemName: matchOK ? "circle.fill" : "circle")
                                .font(.caption2)
                                .foregroundStyle(matchOK ? .purple : (dimmed ? Color.secondary.opacity(0.4) : .secondary))
                            Text(sample.name)
                                .font(.caption2.monospaced())
                                .foregroundStyle(dimmed ? Color.secondary.opacity(0.55) : Color.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text("\(Int((sample.match * 100).rounded()))%")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(matchOK ? .purple : .secondary)
                            Text(formatSize(sample.size))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: minSizeMB)
        .animation(.easeInOut(duration: 0.18), value: semanticThreshold)
    }
}
