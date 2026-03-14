//
//  ThanksForUsingSortyView.swift
//  Sorty
//
//  Appreciation window with interactive stats and liquid glass styling.
//

import SwiftUI
import AppKit

struct ThanksForUsingSortyView: View {
    static let preferredWindowWidth: CGFloat = 500
    static let preferredWindowHeight: CGFloat = 620

    @State private var iconHovered = false
    @State private var heartHovered = false
    @State private var hoveredStatID: String?
    @State private var selectedStatID: String?
    @State private var stats = UserStatsSnapshot.load()
    @State private var isHeartBeating = false

    var body: some View {
        VStack(spacing: 18) {
            header
            beatingHeart
            statsTable
        }
        .padding(22)
        .frame(width: Self.preferredWindowWidth, height: Self.preferredWindowHeight)
        .modifier(ThanksGlassBackground())
        .onAppear {
            stats = UserStatsSnapshot.load()
            isHeartBeating = true
            HapticFeedbackManager.shared.selection()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 82, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .scaleEffect(iconHovered ? 1.04 : 1.0)
                .animation(.easeInOut(duration: 0.18), value: iconHovered)
                .onHover { hovering in
                    iconHovered = hovering
                    if hovering {
                        HapticFeedbackManager.shared.light()
                    }
                }

            Text("Thanks for using Sorty")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
        }
    }

    private var beatingHeart: some View {
        Circle()
            .fill(Color.clear)
            .frame(width: 130, height: 130)
            .modifier(LiquidSurface(cornerRadius: 65))
            .overlay(alignment: .center) {
                Image(systemName: "heart.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(heartHovered ? Color.pink : Color.red)
                    .scaleEffect(isHeartBeating ? (heartHovered ? 1.14 : 1.04) : 0.92)
                    .shadow(color: Color.red.opacity(0.22), radius: 18, y: 8)
                    .animation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true), value: isHeartBeating)
                    .animation(.spring(response: 0.2, dampingFraction: 0.78), value: heartHovered)
            }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .contentShape(Circle())
        .onHover { hovering in
            heartHovered = hovering
            if hovering {
                HapticFeedbackManager.shared.selection()
            }
        }
        .onTapGesture {
            HapticFeedbackManager.shared.tap()
        }
        .accessibilityIdentifier("thanksWindowHeart")
    }

    private var statsTable: some View {
        VStack(alignment: .center, spacing: 10) {
            Text("Your Key Stats")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: 0) {
                statsRow(left: statItems[0], right: statItems[1])
                Divider()
                statsRow(left: statItems[2], right: statItems[3])
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .modifier(LiquidSurface(cornerRadius: 18))
            .onHover { hovering in
                if !hovering {
                    hoveredStatID = nil
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func statsRow(left: StatItem, right: StatItem) -> some View {
        HStack(spacing: 0) {
            statsCell(item: left)
            Divider()
            statsCell(item: right)
        }
        .frame(height: 76)
    }

    private func statsCell(item: StatItem) -> some View {
        let isHighlighted = hoveredStatID == item.id || selectedStatID == item.id

        return VStack(alignment: .leading, spacing: 4) {
            Text(item.value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(item.title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(isHighlighted ? Color.white.opacity(0.09) : Color.clear)
        .animation(.easeInOut(duration: 0.16), value: isHighlighted)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredStatID = item.id
                HapticFeedbackManager.shared.light()
            } else if hoveredStatID == item.id {
                hoveredStatID = nil
            }
        }
        .onTapGesture {
            selectedStatID = (selectedStatID == item.id) ? nil : item.id
            HapticFeedbackManager.shared.tap()
        }
        .accessibilityIdentifier("thanksStat_\(item.id)")
    }

    private var statItems: [StatItem] {
        [
            StatItem(id: "sessions", title: "Sessions", value: stats.sessions.formatted()),
            StatItem(id: "filesOrganized", title: "Files Organized", value: stats.filesOrganized.formatted()),
            StatItem(id: "foldersCreated", title: "Folders Created", value: stats.foldersCreated.formatted()),
            StatItem(id: "successRate", title: "Success Rate", value: "\(stats.successRatePercent)%")
        ]
    }
}

private struct StatItem: Identifiable {
    let id: String
    let title: String
    let value: String
}

private struct LiquidSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                }
        }
    }
}

private struct ThanksGlassBackground: ViewModifier {
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

struct UserStatsSnapshot {
    let sessions: Int
    let filesOrganized: Int
    let foldersCreated: Int
    let successRate: Double
    let activeDays: Int

    var successRatePercent: Int {
        Int((successRate * 100).rounded())
    }

    static func load(userDefaults: UserDefaults = .standard) -> UserStatsSnapshot {
        guard
            let data = userDefaults.data(forKey: "organizationHistory"),
            let entries = try? JSONDecoder().decode([OrganizationHistoryEntry].self, from: data)
        else {
            return UserStatsSnapshot(sessions: 0, filesOrganized: 0, foldersCreated: 0, successRate: 0, activeDays: 0)
        }

        let completedEntries = entries.filter { $0.status == .completed }
        let sessions = entries.count
        let filesOrganized = completedEntries.reduce(0) { $0 + $1.filesOrganized }
        let foldersCreated = completedEntries.reduce(0) { $0 + $1.foldersCreated }
        let successfulCount = completedEntries.count
        let successRate = sessions > 0 ? Double(successfulCount) / Double(sessions) : 0
        let calendar = Calendar.current
        let activeDays = Set(entries.map { calendar.startOfDay(for: $0.timestamp) }).count

        return UserStatsSnapshot(
            sessions: sessions,
            filesOrganized: filesOrganized,
            foldersCreated: foldersCreated,
            successRate: successRate,
            activeDays: activeDays
        )
    }
}

#Preview {
    ThanksForUsingSortyView()
}
