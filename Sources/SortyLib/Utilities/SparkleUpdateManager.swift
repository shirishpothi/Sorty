//
//  SparkleUpdateManager.swift
//  Sorty
//
//  Sparkle framework integration for automatic in-app updates
//

import AppKit
import Combine
import Foundation
import SwiftUI

#if canImport(Sparkle)
import Sparkle
#endif

public enum SparkleUpdateFeed {
    public static let nightlyUpdatesEnabledKey = "nightlyUpdatesEnabled"
    public static let stableAppcastURLString = "https://github.com/sorty-organizer/Sorty/releases/latest/download/appcast-v2.xml"
    public static let nightlyAppcastURLString = "https://github.com/sorty-organizer/Sorty/releases/download/nightly/appcast-nightly.xml"
}

enum SparkleVersionHistoryLink {
    private static let changelogURL = URL(
        string: "https://sorty-organizer.github.io/Sorty/changelog/"
    )!

    static func url(for version: String?) -> URL {
        guard let version else { return changelogURL }

        let versionSlug = version
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "-")

        guard !versionSlug.isEmpty else { return changelogURL }
        return URL(string: "\(changelogURL.absoluteString)#version-\(versionSlug)") ?? changelogURL
    }
}

@MainActor
public class SparkleUpdateManager: ObservableObject {

    @Published public var canCheckForUpdates = false
    @Published public var lastCheckDate: Date?
    @Published public var updateState: UpdateState = .idle
    @Published public private(set) var updateChannel: UpdateChannel = .current

    public enum UpdateChannel: String, Equatable {
        case stable
        case nightly

        public static var current: UpdateChannel {
            UserDefaults.standard.bool(forKey: SparkleUpdateFeed.nightlyUpdatesEnabledKey) ? .nightly : .stable
        }

        public var displayName: String {
            switch self {
            case .stable:
                return "Stable"
            case .nightly:
                return "Nightly"
            }
        }
    }

    public enum UpdateState: Equatable {
        case idle
        case checking
        case available(version: String, releaseNotes: String?)
        case upToDate
        case error(String)
        case downloading
        case readyToInstall
        case installing
        case disabled
    }

    #if canImport(Sparkle)
    private var updater: SPUUpdater?
    private let updaterDelegate: SparkleUpdaterDelegate
    private let userDriverDelegate: SparkleUserDriverDelegate
    private let userDriver: SparkleUserDriver
    #else
    private var updater: Any?
    private let updaterDelegate: Any?
    private let userDriverDelegate: Any?
    private let userDriver: Any?
    #endif

    // UserDefaults key for persisting last check date
    private static let lastAutoCheckKey = "lastSparkleUpdateCheckDate"
    private var lastObservedUpdateChannel = UpdateChannel.current
    private var hasRequestedLaunchCheck = false

    public init() {
        // Restore last check date
        if let savedDate = UserDefaults.standard.object(forKey: Self.lastAutoCheckKey) as? Date {
            self.lastCheckDate = savedDate
        }

        #if canImport(Sparkle)
        // Create delegates
        let updaterDelegate = SparkleUpdaterDelegate()
        let userDriverDelegate = SparkleUserDriverDelegate()
        self.updaterDelegate = updaterDelegate
        self.userDriverDelegate = userDriverDelegate
        self.userDriver = SparkleUserDriver(
            hostBundle: .main,
            delegate: userDriverDelegate
        )
        self.updateChannel = Self.UpdateChannel.current

        // Set up state observation
        updaterDelegate.stateCallback = { [weak self] state in
            self?.updateState = state
        }
        userDriver.stateCallback = { [weak self] state in
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
        self.userDriver = nil
        updateState = .disabled
        #endif

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUserDefaultsDidChangeNotification(_:)),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc nonisolated private func handleUserDefaultsDidChangeNotification(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.handleUserDefaultsDidChange()
        }
    }

    private func handleUserDefaultsDidChange() {
        let currentUpdateChannel = UpdateChannel.current

        if currentUpdateChannel != lastObservedUpdateChannel {
            lastObservedUpdateChannel = currentUpdateChannel
            updateChannel = currentUpdateChannel
            LogManager.shared.log("Sparkle update channel changed to \(currentUpdateChannel.displayName)", category: "SparkleUpdateManager")
        }
    }

    #if canImport(Sparkle)
    private func initializeSparkle() throws {
        // Check if we have a valid app bundle with SUFeedURL configured
        guard Bundle.main.infoDictionary?["SUFeedURL"] != nil else {
            throw SparkleError.noFeedURLConfigured
        }
        
        LogManager.shared.log("Initializing Sparkle updater controller...", category: "SparkleUpdateManager")

        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: updaterDelegate
        )
        try updater.start()
        self.updater = updater

        // Bind canCheckForUpdates to the updater's publisher
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    private enum SparkleError: LocalizedError {
        case noFeedURLConfigured

        var errorDescription: String? {
            switch self {
            case .noFeedURLConfigured:
                return "No SUFeedURL configured in Info.plist"
            }
        }
    }
    #endif

    /// Check for updates immediately
    public func checkForUpdates() {
        #if canImport(Sparkle)
        guard let updater else {
            LogManager.shared.log("Cannot check for updates - Sparkle is disabled", level: .warning, category: "SparkleUpdateManager")
            return
        }

        if updater.sessionInProgress {
            updater.checkForUpdates()
            return
        }

        updateState = .checking
        updater.checkForUpdates()
        recordCheckDate()
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
        recordCheckDate()
        #else
        LogManager.shared.log("Sparkle is not available in this build", level: .warning, category: "SparkleUpdateManager")
        updateState = .disabled
        #endif
    }

    /// Check for updates once per app launch so the title-bar update control does
    /// not depend on the user opening Sparkle's interactive update window first.
    public func checkOnLaunchIfNeeded(minimumInterval: TimeInterval = 0) {
        guard !hasRequestedLaunchCheck else { return }
        hasRequestedLaunchCheck = true

        // Skip if Sparkle is disabled
        #if canImport(Sparkle)
        guard let updater, updater.automaticallyChecksForUpdates else { return }
        #else
        return
        #endif

        // Skip if already checking
        guard updateState != .checking else { return }

        // Check if enough time has passed since last check
        if minimumInterval > 0,
           let lastCheck = UserDefaults.standard.object(forKey: Self.lastAutoCheckKey) as? Date {
            let elapsed = Date.now.timeIntervalSince(lastCheck)
            if elapsed < minimumInterval {
                LogManager.shared.log("Skipping auto-update check, last check was \(Int(elapsed / 60)) minutes ago", category: "SparkleUpdateManager")
                return
            }
        }

        LogManager.shared.log("Performing automatic update check on launch", category: "SparkleUpdateManager")
        checkForUpdatesInBackground()
    }

    /// Starts downloading the update already discovered by the background check.
    /// Sparkle continues to own download, validation, installation, and relaunch.
    @discardableResult
    public func installAvailableUpdate() -> Bool {
        #if canImport(Sparkle)
        guard userDriver.installPendingUpdate() else {
            checkForUpdates()
            return false
        }
        return true
        #else
        return false
        #endif
    }

    /// Brings Sparkle's current download or installation status window forward.
    public func showUpdateInFocus() {
        #if canImport(Sparkle)
        updater?.checkForUpdates()
        #endif
    }

    private func recordCheckDate() {
        let checkDate = Date.now
        lastCheckDate = checkDate
        UserDefaults.standard.set(checkDate, forKey: Self.lastAutoCheckKey)
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
        
        // Log detailed error information for debugging
        let nsError = error as NSError
        let userInfo = nsError.userInfo
        let underlyingError = userInfo[NSUnderlyingErrorKey] as? Error
        let underlyingMessage = underlyingError?.localizedDescription ?? "None"
        
        LogManager.shared.log("Sparkle update failed: \(message). Underlying: \(underlyingMessage). Code: \(nsError.code)", level: .error, category: "SparkleUpdateManager")
        
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
        if UserDefaults.standard.bool(forKey: SparkleUpdateFeed.nightlyUpdatesEnabledKey) {
            return ["nightly"]
        }

        return []
    }

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        if UserDefaults.standard.bool(forKey: SparkleUpdateFeed.nightlyUpdatesEnabledKey) {
            return SparkleUpdateFeed.nightlyAppcastURLString
        }

        return SparkleUpdateFeed.stableAppcastURLString
    }
}

// MARK: - Traffic-Light User Driver

/// Holds a scheduled update at Sparkle's first user choice so the orange
/// title-bar control can begin the download without showing the full update
/// alert. Once the download begins, Sparkle's standard status UI takes over.
@MainActor
private final class SparkleUserDriver: SPUStandardUserDriver {
    var stateCallback: ((SparkleUpdateManager.UpdateState) -> Void)?

    private var pendingAppcastItem: SUAppcastItem?
    private var pendingState: SPUUserUpdateState?
    private var pendingReply: ((SPUUserUpdateChoice) -> Void)?
    private var isHoldingScheduledUpdate = false

    override func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        let stateAwareReply: (SPUUserUpdateChoice) -> Void = { [weak self] choice in
            switch choice {
            case .install:
                self?.stateCallback?(.downloading)
            case .dismiss, .skip:
                self?.stateCallback?(.idle)
            @unknown default:
                self?.stateCallback?(.idle)
            }
            reply(choice)
        }

        guard !state.userInitiated else {
            super.showUpdateFound(with: appcastItem, state: state, reply: stateAwareReply)
            return
        }

        pendingAppcastItem = appcastItem
        pendingState = state
        pendingReply = stateAwareReply
        isHoldingScheduledUpdate = true
    }

    func installPendingUpdate() -> Bool {
        guard let appcastItem = pendingAppcastItem else { return false }

        if appcastItem.isInformationOnlyUpdate {
            presentPendingUpdate()
        } else {
            let reply = pendingReply
            clearPendingUpdate()
            reply?(.install)
        }
        return true
    }

    override func showUpdateInFocus() {
        if isHoldingScheduledUpdate {
            presentPendingUpdate()
        }
        super.showUpdateInFocus()
    }

    override func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        guard !isHoldingScheduledUpdate else { return }
        super.showUpdateReleaseNotes(with: downloadData)
    }

    override func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        guard !isHoldingScheduledUpdate else { return }
        super.showUpdateReleaseNotesFailedToDownloadWithError(error)
    }

    override func showDownloadInitiated(cancellation: @escaping () -> Void) {
        stateCallback?(.downloading)
        super.showDownloadInitiated(cancellation: cancellation)
    }

    override func showDownloadDidStartExtractingUpdate() {
        stateCallback?(.downloading)
        super.showDownloadDidStartExtractingUpdate()
    }

    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        stateCallback?(.readyToInstall)
        super.showReady(toInstallAndRelaunch: reply)
    }

    override func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        stateCallback?(.installing)
        super.showInstallingUpdate(
            withApplicationTerminated: applicationTerminated,
            retryTerminatingApplication: retryTerminatingApplication
        )
    }

    override func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        stateCallback?(.error(error.localizedDescription))
        super.showUpdaterError(error, acknowledgement: acknowledgement)
    }

    override func dismissUpdateInstallation() {
        clearPendingUpdate()
        super.dismissUpdateInstallation()
    }

    private func presentPendingUpdate() {
        guard let appcastItem = pendingAppcastItem,
              let state = pendingState,
              let reply = pendingReply else { return }

        clearPendingUpdate()
        super.showUpdateFound(with: appcastItem, state: state, reply: reply)
    }

    private func clearPendingUpdate() {
        pendingAppcastItem = nil
        pendingState = nil
        pendingReply = nil
        isHoldingScheduledUpdate = false
    }
}

// MARK: - User Driver Delegate

private class SparkleUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    func standardUserDriverShowVersionHistory(for _: SUAppcastItem) {
        let installedVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        let versionHistoryURL = SparkleVersionHistoryLink.url(for: installedVersion)

        Task { @MainActor in
            NSWorkspace.shared.open(versionHistoryURL)
        }
    }

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
