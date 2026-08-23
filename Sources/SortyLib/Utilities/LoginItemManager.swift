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
    public nonisolated(unsafe) static let backgroundAgentPlistName = "com.sorty.app.background-agent.plist"
    public nonisolated(unsafe) static let legacyBackgroundAgentPlistName = "com.sorty.app.plist"
    public nonisolated(unsafe) static let backgroundAgentServiceLabel = "com.sorty.app.background-agent"
    public nonisolated(unsafe) static let backgroundAgentBundleProgram = "Contents/MacOS/Sorty"
    private nonisolated(unsafe) static let registeredBackgroundAgentBundleProgramKey = "registeredBackgroundAgentBundleProgram"

    @Published public var isLaunchAtLoginEnabled: Bool = false
    @Published public var isBackgroundAgentEnabled: Bool = false
    @Published public var registrationStatus: String = "Unknown"
    @Published public var agentStatus: String = "Unknown"

    private var cancellables = Set<AnyCancellable>()

    private init() {
        refreshStatus()
        setupObservations()
    }

    public nonisolated static func backgroundAgentConfigurationIssues(
        label: String,
        bundleProgram: String,
        mainAppServiceLabel: String
    ) -> [String] {
        var issues: [String] = []

        if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Background agent label is missing")
        } else if label == mainAppServiceLabel {
            issues.append("Background agent label collides with the main app service label")
        }

        if bundleProgram.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Background agent BundleProgram is missing")
        } else if bundleProgram != backgroundAgentBundleProgram {
            issues.append("Background agent BundleProgram must remain \(backgroundAgentBundleProgram)")
        }

        return issues
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
                // Let the control that changed this setting render its new state
                // before ServiceManagement performs potentially blocking work.
                await Task.yield()
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
        let agent = SMAppService.agent(plistName: Self.backgroundAgentPlistName)
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
        
        if launchAtLogin && (mainAppStatus == .notRegistered || mainAppStatus == .notFound) {
            try? SMAppService.mainApp.register()
            DebugLogger.log("Registered main app service (Login Item)")
        } else if launchAtLogin && mainAppStatus == .requiresApproval {
            DebugLogger.log("Login item registration requires user approval in System Settings")
        } else if !launchAtLogin && (mainAppStatus == .enabled || mainAppStatus == .requiresApproval) {
            try? SMAppService.mainApp.unregister()
            DebugLogger.log("Unregistered main app service (Login Item)")
        }

        // Migrate off the legacy agent plist that reused the app's service label.
        let legacyAgent = SMAppService.agent(plistName: Self.legacyBackgroundAgentPlistName)
        let legacyAgentStatus = legacyAgent.status
        if legacyAgentStatus == .enabled || legacyAgentStatus == .requiresApproval {
            do {
                try legacyAgent.unregister()
                DebugLogger.log("Removed legacy Sorty background agent registration")
            } catch {
                DebugLogger.log("Failed to remove legacy background agent registration: \(error.localizedDescription)")
            }
        }

        // 2. Sync Background Activity (Agent)
        // Background permission is required for keepInBackground logic to work reliably
        // Decoupled from showMenuBarExtra to give user control over System Settings entry
        let agent = SMAppService.agent(plistName: Self.backgroundAgentPlistName)
        let shouldBeBackgroundAgent = keepInBackground
        let agentCurrentStatus = agent.status
        let registeredBundleProgram = UserDefaults.standard.string(forKey: Self.registeredBackgroundAgentBundleProgramKey)
        let needsAgentRegistrationRefresh = registeredBundleProgram != Self.backgroundAgentBundleProgram

        if shouldBeBackgroundAgent && agentCurrentStatus == .enabled && needsAgentRegistrationRefresh {
            do {
                try agent.unregister()
                try agent.register()
                UserDefaults.standard.set(Self.backgroundAgentBundleProgram, forKey: Self.registeredBackgroundAgentBundleProgramKey)
                DebugLogger.log("Refreshed agent service registration (Background Activity)")
            } catch {
                DebugLogger.log("Failed to refresh background agent registration: \(error.localizedDescription)")
            }
        } else if shouldBeBackgroundAgent && (agentCurrentStatus == .notRegistered || agentCurrentStatus == .notFound) {
            do {
                try agent.register()
                UserDefaults.standard.set(Self.backgroundAgentBundleProgram, forKey: Self.registeredBackgroundAgentBundleProgramKey)
                DebugLogger.log("Registered agent service (Background Activity)")
            } catch {
                DebugLogger.log("Failed to register background agent: \(error.localizedDescription)")
            }
        } else if shouldBeBackgroundAgent && agentCurrentStatus == .requiresApproval {
            DebugLogger.log("Background agent registration requires user approval in System Settings")
        } else if !shouldBeBackgroundAgent && (agentCurrentStatus == .enabled || agentCurrentStatus == .requiresApproval) {
            do {
                try agent.unregister()
                UserDefaults.standard.removeObject(forKey: Self.registeredBackgroundAgentBundleProgramKey)
                DebugLogger.log("Unregistered agent service (Background Activity)")
            } catch {
                DebugLogger.log("Failed to unregister background agent: \(error.localizedDescription)")
            }
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
