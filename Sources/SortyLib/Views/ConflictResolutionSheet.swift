//
//  ConflictResolutionSheet.swift
//  Sorty
//
//  Smart Conflict Resolution UI - shows one conflict at a time with action buttons
//

import SwiftUI

public struct ConflictResolutionSheet: View {
    @ObservedObject var manager: ConflictResolutionManager

    @State private var currentIndex: Int = 0
    @State private var applyToAllChecked: Bool = false

    private var totalConflicts: Int {
        manager.pendingConflicts.count
    }

    private var unresolvedConflicts: [FileConflict] {
        manager.pendingConflicts.filter { manager.resolutions[$0.id] == nil }
    }

    private var currentConflict: FileConflict? {
        unresolvedConflicts.first
    }

    private var resolvedCount: Int {
        manager.resolutions.count
    }

    public init(manager: ConflictResolutionManager) {
        self.manager = manager
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
                .padding()
                .background(.ultraThinMaterial)

            Divider()

            if let conflict = currentConflict {
                conflictDetail(conflict)
                    .padding()

                Divider()

                footer(conflict)
                    .padding()
                    .background(.ultraThinMaterial)
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                    Text("All conflicts resolved")
                        .font(.headline)
                }
                Spacer()
            }
        }
        .frame(width: 520, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
        .accessibilityIdentifier("ConflictResolutionSheet")
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text("File Conflict")
                    .font(.headline)
                Text("Conflict \(resolvedCount + 1) of \(totalConflicts)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ProgressView(value: Double(resolvedCount), total: Double(max(totalConflicts, 1)))
                .frame(width: 80)
        }
    }

    // MARK: - Conflict Detail

    private func conflictDetail(_ conflict: FileConflict) -> some View {
        VStack(spacing: 16) {
            Text("A file already exists at the destination:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                fileCard(
                    label: "Source",
                    url: conflict.sourceURL,
                    name: conflict.sourceName,
                    size: conflict.sourceSize,
                    date: conflict.sourceDate
                )

                Image(systemName: "arrow.right")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                fileCard(
                    label: "Destination",
                    url: conflict.destinationURL,
                    name: conflict.destinationName,
                    size: conflict.destinationSize,
                    date: conflict.destinationDate
                )
            }
        }
    }

    private func fileCard(label: String, url: URL, name: String, size: Int64, date: Date?) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            FileThumbnailView(url: url, size: CGSize(width: 48, height: 48))

            Text(name)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let date = date {
                Text(date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    // MARK: - Footer

    private func footer(_ conflict: FileConflict) -> some View {
        VStack(spacing: 12) {
            Toggle("Apply to all remaining conflicts", isOn: $applyToAllChecked)
                .font(.caption)
                .toggleStyle(.checkbox)

            HStack(spacing: 12) {
                Button {
                    resolve(conflict, action: .skip)
                } label: {
                    Label("Skip", systemImage: "forward.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("ConflictSkipButton")

                Button {
                    resolve(conflict, action: .keepBoth)
                } label: {
                    Label("Keep Both", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("ConflictKeepBothButton")

                Button {
                    resolve(conflict, action: .overwrite)
                } label: {
                    Label("Overwrite", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityIdentifier("ConflictOverwriteButton")
            }
        }
    }

    // MARK: - Actions

    private func resolve(_ conflict: FileConflict, action: ConflictAction) {
        if applyToAllChecked {
            manager.resolveAll(action: action)
        } else {
            manager.resolveConflict(conflict.id, action: action)
        }
    }
}
