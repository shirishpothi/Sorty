//
//  LoginItemManager.swift
//  Sorty
//
//  SMAppService-based login item management for macOS 13+
//

import Foundation
import ServiceManagement
import AppKit
import Combine

@MainActor
public class LoginItemManager: ObservableObject {

    public static let shared = LoginItemManager()

    @Published public var isLaunchAtLoginEnabled: Bool = false
    @Published public var isBackgroundAgentEnabled: Bool = false
    @Published public var registrationStatus: String = "Unknown"
    @Published public var agentStatus: String = "Unknown"

    private var cancellables = Set<AnyCancellable>()

    private init() {
        refreshStatus()
        setupObservations()
    }

    // MARK: - Observations

    private func setupObservations() {
        // Observe UserDefaults for background and login item settings
        // This ensures system registration stays in sync even when main window is closed
        
        Publishers.Merge3(
            UserDefaults.standard.publisher(for: \.keepInBackground),
            UserDefaults.standard.publisher(for: \.launchAtLogin),
            UserDefaults.standard.publisher(for: \.showMenuBarExtra)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let keepInBackground = UserDefaults.standard.bool(forKey: "keepInBackground")
                let launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
                let showMenuBarExtra = UserDefaults.standard.bool(forKey: "showMenuBarExtra")
                
                self.syncServiceRegistration(
                    launchAtLogin: launchAtLogin,
                    keepInBackground: keepInBackground,
                    showMenuBarExtra: showMenuBarExtra
                )
            }
        }
        .store(in: &cancellables)
    }

    // MARK: - Status

    /// Refreshes the current login item registration status from SMAppService.
    public func refreshStatus() {
        // Main App Status (Launch at Login)
        let status = SMAppService.mainApp.status
        self.isLaunchAtLoginEnabled = (status == .enabled)
        self.registrationStatus = describe(status)

        // Background Agent Status
        // plist name must include the .plist extension per Apple documentation
        let agent = SMAppService.agent(plistName: "com.sorty.app.plist")
        let aStatus = agent.status
        self.isBackgroundAgentEnabled = (aStatus == .enabled)
        self.agentStatus = describe(aStatus)
        
        DebugLogger.log("Login Item status: Main App \(registrationStatus), Background Agent \(agentStatus)")
    }
    
    private func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "Enabled"
        case .notRegistered: return "Not Registered"
        case .notFound: return "Not Found"
        case .requiresApproval: return "Requires Approval"
        @unknown default: return "Unknown"
        }
    }

    // MARK: - Toggle

    /// Toggles the launch-at-login registration state.
    /// Registers the app as a login item if currently disabled, or unregisters it if enabled.
    public func toggleLaunchAtLogin() {
        if isLaunchAtLoginEnabled {
            unregisterService()
        } else {
            registerService()
        }
    }

    /// Synchronizes the SMAppService registration based on current settings.
    /// Launch at login uses mainApp, while background activity uses a LaunchAgent.
    public func syncServiceRegistration(launchAtLogin: Bool, keepInBackground: Bool, showMenuBarExtra: Bool = false) {
        // 1. Sync Login Item (mainApp)
        let mainAppStatus = SMAppService.mainApp.status
        
        if launchAtLogin && mainAppStatus != .enabled {
            try? SMAppService.mainApp.register()
            DebugLogger.log("Registered main app service (Login Item)")
        } else if !launchAtLogin && mainAppStatus == .enabled {
            try? SMAppService.mainApp.unregister()
            DebugLogger.log("Unregistered main app service (Login Item)")
        }

        // 2. Sync Background Activity (Agent)
        // Background permission is required for keepInBackground logic to work reliably
        // Decoupled from showMenuBarExtra to give user control over System Settings entry
        let agent = SMAppService.agent(plistName: "com.sorty.app.plist")
        let shouldBeBackgroundAgent = keepInBackground
        let agentCurrentStatus = agent.status

        if shouldBeBackgroundAgent && agentCurrentStatus != .enabled {
            try? agent.register()
            DebugLogger.log("Registered agent service (Background Activity)")
        } else if !shouldBeBackgroundAgent && agentCurrentStatus == .enabled {
            try? agent.unregister()
            DebugLogger.log("Unregistered agent service (Background Activity)")
        }

        refreshStatus()
    }

    private func registerService() {
        do {
            try SMAppService.mainApp.register()
            DebugLogger.log("Registered app service for background activity/login")
        } catch {
            DebugLogger.log("Failed to register login item: \(error.localizedDescription)")
        }
        refreshStatus()
    }

    private func unregisterService() {
        do {
            try SMAppService.mainApp.unregister()
            DebugLogger.log("Unregistered app service")
        } catch {
            DebugLogger.log("Failed to unregister login item: \(error.localizedDescription)")
        }
        refreshStatus()
    }

    // MARK: - Settings

    /// Opens the macOS Login Items settings pane in System Settings.
    public func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Background Activity
    // Deprecated: use syncServiceRegistration instead
}

// MARK: - UserDefaults Extensions

extension UserDefaults {
    @objc dynamic var keepInBackground: Bool {
        bool(forKey: "keepInBackground")
    }
    
    @objc dynamic var launchAtLogin: Bool {
        bool(forKey: "launchAtLogin")
    }
    
    @objc dynamic var showMenuBarExtra: Bool {
        bool(forKey: "showMenuBarExtra")
    }
}
