import SwiftUI

struct CodexSkillInstallerCard: View {
    @StateObject private var installer = CodexSkillInstaller()

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

                Label(statusText, systemImage: statusImage)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            Spacer(minLength: 12)

            actionView
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemLiquidGlassBackground(cornerRadius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task {
            await installer.refresh()
        }
    }

    @ViewBuilder
    private var actionView: some View {
        switch installer.state {
        case .checking, .installing:
            ProgressView()
                .controlSize(.small)
                .frame(minWidth: 86, minHeight: 28)
                .accessibilityLabel(installer.state == .checking ? "Checking Codex skill" : "Installing Codex skill")
        case .available, .failed:
            Button("Install Skill", action: install)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("experimental.codex-skill.install")
        case .installed:
            Button("Installed", systemImage: "checkmark", action: {})
                .controlSize(.small)
                .disabled(true)
                .accessibilityIdentifier("experimental.codex-skill.installed")
        case .conflict:
            Button("Open Skills Folder", action: installer.openSkillsFolder)
                .controlSize(.small)
                .accessibilityIdentifier("experimental.codex-skill.open-folder")
        case .unavailable:
            Button("Check Again") {
                Task { await installer.refresh(trackUsage: false) }
            }
            .controlSize(.small)
            .accessibilityIdentifier("experimental.codex-skill.retry")
        }
    }

    private var statusText: String {
        switch installer.state {
        case .checking: "Checking Codex…"
        case .available: "Ready to install"
        case .installing: "Installing…"
        case .installed: "Installed in Codex"
        case .conflict: "A different Sorty skill is already installed"
        case .unavailable: "The bundled skill is unavailable in this build"
        case .failed: "Installation failed"
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
}
