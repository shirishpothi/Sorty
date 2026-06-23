//
//  SettingPreviews.swift
//  Sorty
//
//  Live preview components for non-obvious settings.
//  They show what a control will actually do without needing to run a scan.
//

import Foundation
import SwiftUI

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

// MARK: - Workspace Health threshold preview

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
                    .contentTransition(.numericText(value: Double(count)))
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
