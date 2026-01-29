//
//  UpdateDialogView.swift
//  Sorty
//
//  A dedicated dialog for checking and displaying software updates
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
            
            switch appState.updateManager.state {
            case .idle:
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Preparing to check for updates...")
                        .foregroundColor(.secondary)
                }
                .onAppear {
                    Task {
                        await appState.updateManager.checkForUpdates()
                    }
                }
                
            case .checking:
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Checking for updates...")
                        .foregroundColor(.secondary)
                }
                
            case let .available(version, url, notes):
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
                    
                    if let notes = notes, !notes.isEmpty {
                        GroupBox("Release Notes") {
                            ScrollView {
                                Text(notes)
                                    .font(.callout)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 150)
                        }
                    }
                    
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Download Update", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
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
                        Task {
                            await appState.updateManager.checkForUpdates()
                        }
                    }
                    .buttonStyle(.bordered)
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
