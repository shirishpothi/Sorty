//
//  SparkleUpdateManager.swift
//  Sorty
//
//  Sparkle framework integration for automatic in-app updates
//

import Foundation
import SwiftUI
import Combine

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
public class SparkleUpdateManager: ObservableObject {

    @Published public var canCheckForUpdates = false
    @Published public var lastCheckDate: Date?
    @Published public var updateState: UpdateState = .idle

    public enum UpdateState: Equatable {
        case idle
        case checking
        case available(version: String, releaseNotes: String?)
        case upToDate
        case error(String)
        case downloading
        case installing
        case disabled
    }

    #if canImport(Sparkle)
    private var updater: SPUUpdater?
    private var updaterController: SPUStandardUpdaterController?
    private let updaterDelegate: SparkleUpdaterDelegate
    private let userDriverDelegate: SparkleUserDriverDelegate
    #else
    private var updater: Any?
    private var updaterController: Any?
    private let updaterDelegate: Any?
    private let userDriverDelegate: Any?
    #endif

    // UserDefaults key for persisting last check date
    private static let lastAutoCheckKey = "lastSparkleUpdateCheckDate"

    public init() {
        // Restore last check date
        if let savedDate = UserDefaults.standard.object(forKey: Self.lastAutoCheckKey) as? Date {
            self.lastCheckDate = savedDate
        }

        #if canImport(Sparkle)
        // Create delegates
        self.updaterDelegate = SparkleUpdaterDelegate()
        self.userDriverDelegate = SparkleUserDriverDelegate()

        // Set up state observation
        (self.updaterDelegate as? SparkleUpdaterDelegate)?.stateCallback = { [weak self] state in
            self?.updateState = state
        }

        // Initialize Sparkle safely - may fail during development builds
        do {
            try initializeSparkle()
        } catch {
            LogManager.shared.log("Sparkle initialization failed (expected during development builds): \(error.localizedDescription)", level: .warning, category: "SparkleUpdateManager")
            updateState = .disabled
        }
        #else
        self.updaterDelegate = nil
        self.userDriverDelegate = nil
        updateState = .disabled
        #endif
    }

    #if canImport(Sparkle)
    private func initializeSparkle() throws {
        // Check if we have a valid app bundle with SUFeedURL configured
        guard Bundle.main.infoDictionary?["SUFeedURL"] != nil else {
            throw SparkleError.noFeedURLConfigured
        }

        // Initialize the updater controller
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self.updaterDelegate as? SPUUpdaterDelegate,
            userDriverDelegate: self.userDriverDelegate as? SPUStandardUserDriverDelegate
        )

        guard let controller = updaterController as? SPUStandardUpdaterController else {
            throw SparkleError.controllerInitializationFailed
        }

        self.updater = controller.updater

        // Bind canCheckForUpdates to the updater's publisher
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    private enum SparkleError: LocalizedError {
        case noFeedURLConfigured
        case controllerInitializationFailed

        var errorDescription: String? {
            switch self {
            case .noFeedURLConfigured:
                return "No SUFeedURL configured in Info.plist"
            case .controllerInitializationFailed:
                return "Failed to initialize Sparkle updater controller"
            }
        }
    }
    #endif

    /// Check for updates immediately
    public func checkForUpdates() {
        #if canImport(Sparkle)
        guard let controller = updaterController as? SPUStandardUpdaterController else {
            LogManager.shared.log("Cannot check for updates - Sparkle is disabled", level: .warning, category: "SparkleUpdateManager")
            return
        }
        updateState = .checking
        controller.checkForUpdates(nil)
        lastCheckDate = Date()
        UserDefaults.standard.set(Date(), forKey: Self.lastAutoCheckKey)
        #else
        LogManager.shared.log("Sparkle is not available in this build", level: .warning, category: "SparkleUpdateManager")
        updateState = .disabled
        #endif
    }

    /// Check for updates in the background (no UI)
    public func checkForUpdatesInBackground() {
        #if canImport(Sparkle)
        guard let updater = self.updater as? SPUUpdater else {
            LogManager.shared.log("Cannot check for updates in background - Sparkle is disabled", level: .warning, category: "SparkleUpdateManager")
            return
        }
        updateState = .checking
        updater.checkForUpdatesInBackground()
        lastCheckDate = Date()
        UserDefaults.standard.set(Date(), forKey: Self.lastAutoCheckKey)
        #else
        LogManager.shared.log("Sparkle is not available in this build", level: .warning, category: "SparkleUpdateManager")
        updateState = .disabled
        #endif
    }

    /// Check for updates on app launch if sufficient time has passed
    /// - Parameter minimumInterval: Minimum time between automatic checks (default: 24 hours)
    public func checkOnLaunchIfNeeded(minimumInterval: TimeInterval = 24 * 60 * 60) {
        // Skip if Sparkle is disabled
        #if canImport(Sparkle)
        guard updater != nil else { return }
        #else
        return
        #endif

        // Skip if already checking
        guard updateState != .checking else { return }

        // Check if enough time has passed since last check
        if let lastCheck = UserDefaults.standard.object(forKey: Self.lastAutoCheckKey) as? Date {
            let elapsed = Date().timeIntervalSince(lastCheck)
            if elapsed < minimumInterval {
                LogManager.shared.log("Skipping auto-update check, last check was \(Int(elapsed / 60)) minutes ago", category: "SparkleUpdateManager")
                return
            }
        }

        LogManager.shared.log("Performing automatic update check on launch", category: "SparkleUpdateManager")
        checkForUpdatesInBackground()
    }

    /// Reset state to idle
    public func resetState() {
        updateState = .idle
    }
}

#if canImport(Sparkle)
// MARK: - Updater Delegate

@MainActor
private class SparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    var stateCallback: ((SparkleUpdateManager.UpdateState) -> Void)?

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        let releaseNotes = item.itemDescription
        Task { @MainActor in
            self.stateCallback?(.available(version: version, releaseNotes: releaseNotes))
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            self.stateCallback?(.upToDate)
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.stateCallback?(.error(message))
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        Task { @MainActor in
            self.stateCallback?(.installing)
        }
    }

    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        LogManager.shared.log("Application will relaunch after update", category: "SparkleUpdateManager")
    }

    nonisolated func versionComparator(for updater: SPUUpdater) -> SUVersionComparison? {
        return nil // Use default version comparison
    }

    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        return ["default"] // Only check default channel
    }
}

// MARK: - User Driver Delegate

private class SparkleUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    func standardUserDriverShouldHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) -> Bool {
        return true // Let Sparkle handle the UI
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        LogManager.shared.log("Sparkle will show update dialog for version \(update.displayVersionString)", category: "SparkleUpdateManager")
    }

    func standardUserDriverShouldHandleUpdateFound(forUpdate update: SUAppcastItem, state: SPUUserUpdateState) -> Bool {
        return true // Let Sparkle handle showing the update found UI
    }

    func standardUserDriverWillHandleUpdateFound(forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        LogManager.shared.log("Sparkle found update: \(update.displayVersionString)", category: "SparkleUpdateManager")
    }
}
#endif
