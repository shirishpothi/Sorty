//
//  UpdateDialogView.swift
//  Sorty
//
//  A dedicated dialog for checking and displaying software updates via Sparkle
//

import SwiftUI

public struct UpdateDialogView: View {
    @EnvironmentObject var appState: AppState
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.title)
                    .foregroundColor(.accentColor)
                Text("Software Update")
                    .font(.headline)
            }
            
            Divider()
            
            switch appState.updateManager.updateState {
            case .idle:
                HStack {
                    SortyGradientCircularLoader(size: 12, lineWidth: 2.2)
                    Text("Preparing to check for updates...")
                        .foregroundColor(.secondary)
                }
                .onAppear {
                    // Sparkle handles the UI automatically when updates are found
                    // But we trigger the check here
                    appState.updateManager.checkForUpdates()
                }
                
            case .checking:
                HStack {
                    SortyGradientCircularLoader(size: 12, lineWidth: 2.2)
                    Text("Checking for updates...")
                        .foregroundColor(.secondary)
                }
                
            case let .available(version, releaseNotes):
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "gift.fill")
                            .foregroundColor(.green)
                        Text("Update Available!")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    
                    Text("Version \(version) is now available. You have version \(BuildInfo.version).")
                        .foregroundColor(.secondary)
                    
                    if let notes = releaseNotes, !notes.isEmpty {
                        GroupBox("Release Notes") {
                            ScrollView {
                                Text(notes)
                                    .font(.callout)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 150)
                        }
                    }
                    
                    Text("Click the button below to download and install the update automatically.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    
                    // Sparkle handles the actual download/install UI automatically
                    // This button just triggers Sparkle's standard UI
                    Button {
                        appState.updateManager.checkForUpdates()
                    } label: {
                        Label("Download & Install Update", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.sortyProminent)
                }
                
            case .upToDate:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sorty is up to date")
                            .font(.title3)
                            .fontWeight(.medium)
                        Text("You're running the latest version (\(BuildInfo.version)).")
                            .foregroundColor(.secondary)
                            .font(.callout)
                    }
                }
                
            case .downloading:
                HStack {
                    SortyGradientCircularLoader(size: 12, lineWidth: 2.2)
                    Text("Downloading update...")
                        .foregroundColor(.secondary)
                }
                
            case .installing:
                HStack {
                    SortyGradientCircularLoader(size: 12, lineWidth: 2.2)
                    Text("Installing update...")
                        .foregroundColor(.secondary)
                }
                
            case let .error(message):
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.title2)
                        Text("Update Check Failed")
                            .font(.title3)
                            .fontWeight(.medium)
                    }

                    Text(message)
                        .font(.callout)
                        .foregroundColor(.secondary)

                    Button("Try Again") {
                        appState.updateManager.checkForUpdates()
                    }
                    .buttonStyle(.sortyBordered)
                }

            case .disabled:
                HStack {
                    Image(systemName: "gear.badge.xmark")
                        .foregroundColor(.secondary)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Update checking is disabled")
                            .font(.title3)
                            .fontWeight(.medium)
                        Text(NetworkPrivacyPolicy.isInternetPrivacyModeEnabled ? "Internet Privacy Mode is on. Turn it off to check for updates." : "This build doesn't support automatic updates.")
                            .foregroundColor(.secondary)
                            .font(.callout)
                    }
                }
            }
            
            Spacer().frame(height: 8)
            
            Divider()
            
            HStack {
                if let lastCheck = appState.updateManager.lastCheckDate {
                    Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Close") {
                    appState.showUpdateSheet = false
                    appState.updateManager.resetState()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 450)
    }
}
