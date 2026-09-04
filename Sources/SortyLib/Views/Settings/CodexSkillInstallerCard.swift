import SwiftUI

struct CodexSkillInstallerCard: View {
    @SortyHotReload private var hotReload
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var installer = CodexSkillInstaller()
    @State private var isConfirmingRemoval = false
    @State private var isConfirmingReplacement = false
    @State private var isHoveringShowExisting = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.indigo)
                .frame(width: 28, height: 28)
                .background(.indigo.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("Sorty for Codex")
                        .font(.subheadline.weight(.semibold))
                    Text("Experimental")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.1), in: Capsule())
                }

                Text("Install Sorty as a Codex skill for organizing, renaming, duplicate review, and rollback from natural-language requests.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if installer.state != .available {
                    Label(statusText, systemImage: statusImage)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
            }

            Spacer(minLength: 12)

            actionView
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemLiquidGlassBackground(cornerRadius: 12, interactive: false)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            if installer.state == .conflict {
                Button("Remove Existing Skill", role: .destructive) {
                    isConfirmingRemoval = true
                }
                .accessibilityIdentifier("experimental.codex-skill.remove")
                Button("Show in Finder") {
                    installer.revealExistingSkill()
                }
            }
        }
        .task {
            await installer.refresh()
        }
        .confirmationDialog(
            "Remove Sorty from Codex?",
            isPresented: $isConfirmingRemoval
        ) {
            Button("Remove Skill", role: .destructive, action: remove)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Codex will no longer discover the Sorty skill. You can install it again at any time.")
        }
        .confirmationDialog(
            "Replace the existing Sorty skill?",
            isPresented: $isConfirmingReplacement
        ) {
            Button("Replace Skill", role: .destructive, action: replace)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces the Sorty skill currently in your Codex skills folder with the version bundled in Sorty.")
        }
    }

    @ViewBuilder
    private var actionView: some View {
        switch installer.state {
        case .checking, .installing, .replacing, .removing:
            ProgressView()
                .controlSize(.small)
                .frame(minWidth: 86, minHeight: 28)
                .accessibilityLabel(progressLabel)
        case .available, .failed:
            Button("Install Skill", action: install)
                .buttonStyle(.sortyProminent(size: .small))
                .accessibilityIdentifier("experimental.codex-skill.install")
        case .installed:
            Button("Remove Skill", role: .destructive) {
                isConfirmingRemoval = true
            }
            .buttonStyle(.sortyBordered(intent: .destructive, size: .small))
            .accessibilityIdentifier("experimental.codex-skill.remove")
        case .conflict:
            VStack(alignment: .center, spacing: 6) {
                Button("Replace Skill") {
                    isConfirmingReplacement = true
                }
                .buttonStyle(.sortyProminent(intent: .warning, size: .small))
                .accessibilityIdentifier("experimental.codex-skill.replace")

                Button {
                    HapticFeedbackManager.shared.tap()
                    installer.revealExistingSkill()
                } label: {
                    Text("Show Existing Skill")
                        .overlay(alignment: .trailing) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .semibold))
                                .offset(
                                    x: reduceMotion || isHoveringShowExisting ? 14 : 11,
                                    y: reduceMotion || isHoveringShowExisting ? 0 : 3
                                )
                                .scaleEffect(reduceMotion || isHoveringShowExisting ? 1 : 0.75)
                                .opacity(isHoveringShowExisting ? 1 : 0)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82),
                    value: isHoveringShowExisting
                )
                .onHover { hovering in
                    if hovering {
                        HapticFeedbackManager.shared.selection()
                    }
                    isHoveringShowExisting = hovering
                }
                .accessibilityIdentifier("experimental.codex-skill.open-folder")
            }
        case .unavailable:
            Button("Check Again") {
                Task { await installer.refresh(trackUsage: false) }
            }
            .buttonStyle(.sortyBordered(size: .small))
            .accessibilityIdentifier("experimental.codex-skill.retry")
        }
    }

    private var statusText: String {
        switch installer.state {
        case .checking: "Checking Codex…"
        case .available: "Ready to install"
        case .installing: "Installing…"
        case .replacing: "Replacing existing skill…"
        case .removing: "Removing…"
        case .installed: "Installed in Codex"
        case .conflict: "Another Sorty skill is installed. Replace it or review it first."
        case .unavailable: "The bundled skill is unavailable in this build"
        case .failed: "Installation failed"
        }
    }

    private var progressLabel: String {
        switch installer.state {
        case .checking: "Checking Codex skill"
        case .installing: "Installing Codex skill"
        case .replacing: "Replacing Codex skill"
        case .removing: "Removing Codex skill"
        default: "Updating Codex skill"
        }
    }

    private var statusImage: String {
        switch installer.state {
        case .installed: "checkmark.circle.fill"
        case .conflict, .unavailable, .failed: "exclamationmark.triangle.fill"
        default: "circle.dotted"
        }
    }

    private var statusColor: Color {
        switch installer.state {
        case .installed: .green
        case .conflict, .unavailable, .failed: .orange
        default: .secondary
        }
    }

    private func install() {
        Task {
            await installer.install()
            let announcement: String
            if case .installed = installer.state {
                announcement = "Sorty skill installed in Codex"
            } else {
                announcement = statusText
            }
            AccessibilityNotification.Announcement(announcement).post()
        }
    }

    private func replace() {
        Task {
            await installer.replace()
            AccessibilityNotification.Announcement(statusText).post()
        }
    }

    private func remove() {
        Task {
            await installer.remove()
            AccessibilityNotification.Announcement(statusText).post()
        }
    }
}
