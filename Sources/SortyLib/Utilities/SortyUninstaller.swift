//
//  SortyUninstaller.swift
//  Sorty
//
//  One-shot local cleanup for users who want to fully remove Sorty data.
//

import Foundation
import ServiceManagement

public struct SortyUninstallReport: Equatable {
    public let removedPaths: [String]
    public let missingPaths: [String]
    public let failedPaths: [String: String]
    public let didClearDefaults: Bool
    public let didClearKeychain: Bool
    public let didRequestFinderExtensionDisable: Bool
    public let didRequestFinderExtensionStop: Bool
    public let didRequestLoginItemRemoval: Bool
}

public enum SortyUninstaller {
    public static let requestDefaultsKey = "runUninstallerOnNextLaunch"

    private static let bundleIdentifier = "com.sorty.app"
    private static let finderSyncBundleIdentifier = "com.sorty.app.SortyFinderSync"
    private static let appGroupIdentifier = "group.com.sorty.app"

    public static func consumeDefaultsRequestAndRunIfNeeded() -> SortyUninstallReport? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: requestDefaultsKey) else { return nil }

        defaults.set(false, forKey: requestDefaultsKey)
        defaults.synchronize()

        return run()
    }

    public static func run() -> SortyUninstallReport {
        let fileManager = FileManager.default
        let removedServiceRegistrations = removeServiceRegistrations()
        let disabledFinderExtension = runCommand("/usr/bin/pluginkit", arguments: [
            "-e", "ignore",
            "-i", finderSyncBundleIdentifier
        ])
        let stoppedFinderExtension = runCommand("/usr/bin/pkill", arguments: [
            "-f", "SortyFinderSync"
        ])

        let pathResult = removeFilesystemState(
            homeDirectory: fileManager.homeDirectoryForCurrentUser,
            fileManager: fileManager
        )
        let didClearDefaults = clearDefaults()
        let didClearKeychain = KeychainManager.deleteAll()

        return SortyUninstallReport(
            removedPaths: pathResult.removed,
            missingPaths: pathResult.missing,
            failedPaths: pathResult.failed,
            didClearDefaults: didClearDefaults,
            didClearKeychain: didClearKeychain,
            didRequestFinderExtensionDisable: disabledFinderExtension,
            didRequestFinderExtensionStop: stoppedFinderExtension,
            didRequestLoginItemRemoval: removedServiceRegistrations
        )
    }

    public static func cleanupPathCandidates(homeDirectory: URL) -> [URL] {
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)

        var candidates = [
            library.appendingPathComponent("Application Support/Sorty", isDirectory: true),
            library.appendingPathComponent("Application Support/com.sorty.app", isDirectory: true),
            library.appendingPathComponent("Caches/com.sorty.app", isDirectory: true),
            library.appendingPathComponent("Logs/Sorty", isDirectory: true),
            library.appendingPathComponent("Containers/com.sorty.app", isDirectory: true),
            library.appendingPathComponent("Group Containers/group.com.sorty.app", isDirectory: true),
            library.appendingPathComponent("LaunchAgents/com.sorty.app.background-agent.plist"),
            library.appendingPathComponent("LaunchAgents/com.sorty.app.plist"),
            library.appendingPathComponent("Preferences/com.sorty.app.plist"),
        ]

        let byHostPreferences = library.appendingPathComponent("Preferences/ByHost", isDirectory: true)
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: byHostPreferences,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            candidates.append(contentsOf: contents.filter {
                $0.lastPathComponent.hasPrefix("com.sorty.app.")
            })
        }

        return candidates
    }

    static func removeFilesystemState(
        homeDirectory: URL,
        fileManager: FileManager
    ) -> (removed: [String], missing: [String], failed: [String: String]) {
        var removed: [String] = []
        var missing: [String] = []
        var failed: [String: String] = [:]

        for url in cleanupPathCandidates(homeDirectory: homeDirectory) {
            let path = url.path
            guard fileManager.fileExists(atPath: path) else {
                missing.append(path)
                continue
            }

            do {
                try fileManager.removeItem(at: url)
                removed.append(path)
            } catch {
                failed[path] = error.localizedDescription
            }
        }

        return (removed, missing, failed)
    }

    private static func clearDefaults() -> Bool {
        UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        UserDefaults.standard.synchronize()

        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            sharedDefaults.removePersistentDomain(forName: appGroupIdentifier)
            sharedDefaults.synchronize()
        }

        return true
    }

    private static func removeServiceRegistrations() -> Bool {
        var success = true

        success = unregister(SMAppService.mainApp) && success
        success = unregister(SMAppService.agent(plistName: LoginItemManager.backgroundAgentPlistName)) && success
        success = unregister(SMAppService.agent(plistName: LoginItemManager.legacyBackgroundAgentPlistName)) && success

        return success
    }

    private static func unregister(_ service: SMAppService) -> Bool {
        switch service.status {
        case .enabled, .requiresApproval:
            do {
                try service.unregister()
                return true
            } catch {
                return false
            }
        case .notRegistered, .notFound:
            return true
        @unknown default:
            return true
        }
    }

    @discardableResult
    private static func runCommand(_ launchPath: String, arguments: [String]) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 || process.terminationStatus == 1
        } catch {
            return false
        }
    }
}
