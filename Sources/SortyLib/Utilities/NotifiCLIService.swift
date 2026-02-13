//
//  NotifiCLIService.swift
//  Sorty
//
//  A Swift wrapper for NotifiCLI - a macOS CLI tool for actionable, persistent notifications
//  Auto-builds and sets up NotifiCLI from bundled sources on first use.
//  https://github.com/saihgupr/NotifiCLI
//

import Foundation
import AppKit

/// Response from a NotifiCLI notification
public enum NotifiCLIResponse: Sendable, Equatable {
    case action(String)      // User clicked an action button
    case reply(String)       // User typed a reply
    case defaultClick        // User clicked the notification body
    case dismissed           // User dismissed the notification
    case timeout             // Notification timed out (non-persistent)
    case error(String)       // An error occurred
    
    public var isAction: Bool {
        if case .action = self { return true }
        return false
    }
    
    public var actionLabel: String? {
        if case .action(let label) = self { return label }
        return nil
    }
}

/// Configuration for a NotifiCLI notification
public struct NotifiCLIConfig: Sendable {
    public let title: String
    public var subtitle: String?
    public var message: String?
    public var actions: [String]?
    public var image: String?
    public var icon: String?
    public var replyPlaceholder: String?
    public var url: String?
    public var sound: String?
    public var persistent: Bool
    
    public init(
        title: String,
        subtitle: String? = nil,
        message: String? = nil,
        actions: [String]? = nil,
        image: String? = nil,
        icon: String? = nil,
        replyPlaceholder: String? = nil,
        url: String? = nil,
        sound: String? = nil,
        persistent: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.message = message
        self.actions = actions
        self.image = image
        self.icon = icon
        self.replyPlaceholder = replyPlaceholder
        self.url = url
        self.sound = sound
        self.persistent = persistent
    }
}

/// Available system sounds for notifications
public enum NotifiCLISound: String, CaseIterable, Sendable {
    case basso = "Basso"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case glass = "Glass"
    case hero = "Hero"
    case morse = "Morse"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case tink = "Tink"
}

/// Setup status for NotifiCLI
public enum NotifiCLISetupStatus: Sendable {
    case notSetup
    case building
    case ready
    case failed(String)
}

/// Service for sending notifications via NotifiCLI
/// Automatically builds NotifiCLI from bundled sources on first use
public actor NotifiCLIService {
    public static let shared = NotifiCLIService()
    
    // Paths
    private let appSupportDir: URL
    private let notifiCLIAppPath: URL
    private let notifiPersistentAppPath: URL
    private var notificliPath: String?
    private var notifiPersistentPath: String?
    
    // State
    private var setupStatus: NotifiCLISetupStatus = .notSetup
    private var isAvailable: Bool = false
    private var permissionsGranted: Bool = false
    
    private init() {
        // Setup in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appSupportDir = appSupport.appendingPathComponent("Sorty/NotifiCLI")
        notifiCLIAppPath = appSupportDir.appendingPathComponent("SortyNotifications.app")
        notifiPersistentAppPath = appSupportDir.appendingPathComponent("SortyNotificationsPersistent.app")
    }
    
    // MARK: - Public API
    
    /// Get current setup status
    public func getSetupStatus() -> NotifiCLISetupStatus {
        return setupStatus
    }
    
    /// Check if NotifiCLI is available and ready
    public func checkAvailability() async -> Bool {
        if isAvailable && notificliPath != nil {
            return true
        }
        return await ensureSetup()
    }
    
    /// Get the installation status and path
    public func getInstallationInfo() -> (installed: Bool, path: String?) {
        return (isAvailable, notificliPath)
    }
    
    /// Ensure NotifiCLI is set up and ready to use
    /// This will build from bundled sources if needed
    @discardableResult
    public func ensureSetup() async -> Bool {
        // Already ready?
        if isAvailable && notificliPath != nil {
            return true
        }
        
        // Check if already built
        let binaryPath = notifiCLIAppPath.appendingPathComponent("Contents/MacOS/SortyNotifications").path
        let persistentBinaryPath = notifiPersistentAppPath.appendingPathComponent("Contents/MacOS/SortyNotificationsPersistent").path
        
        if FileManager.default.isExecutableFile(atPath: binaryPath) && FileManager.default.isExecutableFile(atPath: persistentBinaryPath) {
            notificliPath = binaryPath
            notifiPersistentPath = persistentBinaryPath
            isAvailable = true
            setupStatus = .ready
            print("NotifiCLIService: Found existing build at \(binaryPath)")
            return true
        }
        
        // Need to build
        setupStatus = .building
        print("NotifiCLIService: Building NotifiCLI from bundled sources...")
        
        do {
            try await buildNotifiCLI()
            notificliPath = binaryPath
            notifiPersistentPath = persistentBinaryPath
            isAvailable = true
            setupStatus = .ready
            
            // Grant permissions by opening the app once
            await grantPermissions()
            
            print("NotifiCLIService: Build complete, ready to use")
            return true
        } catch {
            print("NotifiCLIService: Build failed: \(error)")
            setupStatus = .failed(error.localizedDescription)
            return false
        }
    }
    
    /// Force rebuild of NotifiCLI
    public func rebuild() async -> Bool {
        // Remove existing
        try? FileManager.default.removeItem(at: notifiCLIAppPath)
        try? FileManager.default.removeItem(at: notifiPersistentAppPath)
        isAvailable = false
        notificliPath = nil
        setupStatus = .notSetup
        
        return await ensureSetup()
    }
    
    // MARK: - Build System
    
    private func buildNotifiCLI() async throws {
        let fm = FileManager.default
        
        // Check for required tools upfront
        guard fm.isExecutableFile(atPath: "/usr/bin/swiftc") else {
            throw NotifiCLIError.setupFailed("swiftc not found at /usr/bin/swiftc")
        }
        
        guard fm.isExecutableFile(atPath: "/usr/bin/codesign") else {
            throw NotifiCLIError.setupFailed("codesign not found at /usr/bin/codesign")
        }
        
        // Create directory structure
        try fm.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        
        // Get bundled source
        guard let sourceCode = getBundledSource() else {
            throw NotifiCLIError.sourceNotFound
        }
        
        // Build standard notification app
        try await buildApp(
            name: "SortyNotifications",
            bundleId: "com.sorty.notifications",
            at: notifiCLIAppPath,
            source: sourceCode
        )
        
        // Build persistent notification app (same binary, different bundle ID for alert style)
        try await buildApp(
            name: "SortyNotificationsPersistent",
            bundleId: "com.sorty.notifications.persistent",
            at: notifiPersistentAppPath,
            source: sourceCode
        )
    }
    
    private func buildApp(name: String, bundleId: String, at appPath: URL, source: String) async throws {
        let fm = FileManager.default
        
        // Create app bundle structure
        let contentsDir = appPath.appendingPathComponent("Contents")
        let macosDir = contentsDir.appendingPathComponent("MacOS")
        let resourcesDir = contentsDir.appendingPathComponent("Resources")
        
        try fm.createDirectory(at: macosDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
        
        // Write Info.plist
        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>\(bundleId)</string>
            <key>CFBundleName</key>
            <string>\(name)</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>CFBundleIconFile</key>
            <string>AppIcon</string>
            <key>LSUIElement</key>
            <true/>
            <key>NSUserNotificationAlertStyle</key>
            <string>\(name.contains("Persistent") ? "alert" : "banner")</string>
        </dict>
        </plist>
        """
        try infoPlist.write(to: contentsDir.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        
        // Copy app icon from Sorty bundle if available
        // We look in multiple potential locations for AppIcon.icns
        let potentialIconPaths = [
            Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns").path,
            "/Applications/Sorty.app/Contents/Resources/AppIcon.icns"
        ]
        
        for path in potentialIconPaths {
            if let iconPath = path, fm.fileExists(atPath: iconPath) {
                try? fm.copyItem(atPath: iconPath, toPath: resourcesDir.appendingPathComponent("AppIcon.icns").path)
                break
            }
        }
        
        // Write source file
        let sourceFile = appSupportDir.appendingPathComponent("\(name).swift")
        try source.write(to: sourceFile, atomically: true, encoding: .utf8)
        
        // Compile
        let binaryPath = macosDir.appendingPathComponent(name)
        try await compileSwift(source: sourceFile, output: binaryPath)
        
        // Clean up source file
        try? fm.removeItem(at: sourceFile)
        
        // Code sign
        try await codesign(appPath)
    }
    
    private func compileSwift(source: URL, output: URL) async throws {
        #if arch(x86_64)
        let targetArch = "x86_64"
        #else
        let targetArch = "arm64"
        #endif
        
        try await runProcess(
            executable: "/usr/bin/swiftc",
            arguments: [
                source.path,
                "-o", output.path,
                "-target", "\(targetArch)-apple-macosx11.0",
                "-O"
            ]
        )
    }
    
    private func codesign(_ appPath: URL) async throws {
        try await runProcess(
            executable: "/usr/bin/codesign",
            arguments: ["--force", "--deep", "-s", "-", appPath.path]
        )
    }
    
    private func runProcess(executable: String, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    
                    let errorPipe = Pipe()
                    process.standardError = errorPipe
                    process.standardOutput = FileHandle.nullDevice
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    if process.terminationStatus != 0 {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorStr = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: NotifiCLIError.compilationFailed(errorStr))
                    } else {
                        continuation.resume()
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func grantPermissions() async {
        // Open the app once to trigger macOS permission dialogs
        // This runs in background (LSUIElement = true) so user won't see a window
        guard let path = notificliPath else { return }
        
        let appPath = URL(fileURLWithPath: path)
            .deletingLastPathComponent()  // MacOS
            .deletingLastPathComponent()  // Contents
            .deletingLastPathComponent()  // .app
        
        // Use 'open' to launch the app bundle properly
        do {
            try await runProcess(
                executable: "/usr/bin/open",
                arguments: ["-g", appPath.path]  // -g = don't bring to foreground
            )
            // Give it a moment to request permissions
            try? await Task.sleep(nanoseconds: 500_000_000)
            permissionsGranted = true
        } catch {
            print("NotifiCLIService: Failed to grant permissions: \(error)")
        }
    }
    
    private func getBundledSource() -> String? {
        // Try to read from bundled resources first
        if let url = Bundle.main.url(forResource: "main", withExtension: "swift", subdirectory: "NotifiCLI"),
           let source = try? String(contentsOf: url) {
            return source
        }
        
        // Fallback: embedded source code
        return Self.embeddedNotifiCLISource
    }
    
    // MARK: - Send Notifications
    
    /// Send a notification with the given configuration
    /// Returns the user's response (action clicked, reply text, or dismissal)
    @discardableResult
    public func send(_ config: NotifiCLIConfig) async -> NotifiCLIResponse {
        // Ensure setup
        guard await ensureSetup() else {
            return .error("NotifiCLI setup failed")
        }
        
        // Choose binary based on persistent flag
        let binaryPath: String
        if config.persistent, let persistentPath = notifiPersistentPath,
           FileManager.default.isExecutableFile(atPath: persistentPath) {
            binaryPath = persistentPath
        } else if let path = notificliPath {
            binaryPath = path
        } else {
            return .error("NotifiCLI binary not found")
        }
        
        return await sendWithPath(config, path: binaryPath)
    }
    
    private func sendWithPath(_ config: NotifiCLIConfig, path: String) async -> NotifiCLIResponse {
        var arguments: [String] = []
        
        // Required: title
        arguments.append(contentsOf: ["-title", config.title])
        
        // Message is required
        if let message = config.message, !message.isEmpty {
            arguments.append(contentsOf: ["-message", message])
        } else {
            arguments.append(contentsOf: ["-message", " "]) // Empty message fallback
        }
        
        // Optional parameters
        if let subtitle = config.subtitle, !subtitle.isEmpty {
            arguments.append(contentsOf: ["-subtitle", subtitle])
        }
        
        if let actions = config.actions, !actions.isEmpty {
            arguments.append(contentsOf: ["-actions", actions.joined(separator: ",")])
        }
        
        if let image = config.image, !image.isEmpty {
            arguments.append(contentsOf: ["-image", image])
        }
        
        if let replyPlaceholder = config.replyPlaceholder, !replyPlaceholder.isEmpty {
            arguments.append(contentsOf: ["-reply", replyPlaceholder])
        }
        
        if let url = config.url, !url.isEmpty {
            arguments.append(contentsOf: ["-url", url])
        }
        
        if let sound = config.sound, !sound.isEmpty {
            arguments.append(contentsOf: ["-sound", sound])
        }
        
        print("NotifiCLIService: Sending notification: \(config.title)")
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: path)
                    process.arguments = arguments
                    
                    let outputPipe = Pipe()
                    let errorPipe = Pipe()
                    process.standardOutput = outputPipe
                    process.standardError = errorPipe
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outputData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    
                    if process.terminationStatus != 0 && !errorOutput.isEmpty && !errorOutput.contains("Downloaded") {
                        print("NotifiCLIService: Error output: \(errorOutput)")
                        continuation.resume(returning: .error(errorOutput))
                        return
                    }
                    
                    // Parse the response
                    let response = self.parseResponse(output, config: config)
                    continuation.resume(returning: response)
                    
                } catch {
                    print("NotifiCLIService: Process error: \(error)")
                    continuation.resume(returning: .error(error.localizedDescription))
                }
            }
        }
    }
    
    private nonisolated func parseResponse(_ output: String, config: NotifiCLIConfig) -> NotifiCLIResponse {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            return .timeout
        }
        
        if trimmed == "dismissed" {
            return .dismissed
        }
        
        if trimmed == "default" {
            return .defaultClick
        }
        
        // Check if this matches one of the action buttons
        if let actions = config.actions, actions.contains(trimmed) {
            return .action(trimmed)
        }
        
        // If reply was enabled, treat the output as reply text
        if config.replyPlaceholder != nil {
            return .reply(trimmed)
        }
        
        // Otherwise, treat as an action
        return .action(trimmed)
    }
    
    // MARK: - Convenience Methods
    
    /// Send a simple notification with just title and message
    @discardableResult
    public func sendSimple(
        title: String,
        message: String,
        sound: NotifiCLISound? = nil,
        persistent: Bool = false
    ) async -> NotifiCLIResponse {
        let config = NotifiCLIConfig(
            title: title,
            message: message,
            sound: sound?.rawValue,
            persistent: persistent
        )
        return await send(config)
    }
    
    /// Send a notification with action buttons and wait for response
    @discardableResult
    public func sendWithActions(
        title: String,
        message: String,
        actions: [String],
        sound: NotifiCLISound? = nil,
        persistent: Bool = true
    ) async -> NotifiCLIResponse {
        let config = NotifiCLIConfig(
            title: title,
            message: message,
            actions: actions,
            sound: sound?.rawValue,
            persistent: persistent
        )
        return await send(config)
    }
    
    /// Send a notification that opens a URL when clicked
    public func sendWithURL(
        title: String,
        message: String,
        url: String,
        sound: NotifiCLISound? = nil
    ) async {
        let config = NotifiCLIConfig(
            title: title,
            message: message,
            url: url,
            sound: sound?.rawValue
        )
        _ = await send(config)
    }
    
    /// Send a notification with reply input
    @discardableResult
    public func sendWithReply(
        title: String,
        message: String,
        replyPlaceholder: String,
        persistent: Bool = true
    ) async -> String? {
        let config = NotifiCLIConfig(
            title: title,
            message: message,
            replyPlaceholder: replyPlaceholder,
            persistent: persistent
        )
        let response = await send(config)
        if case .reply(let text) = response {
            return text
        }
        return nil
    }
    
    // MARK: - Fire and Forget (Non-blocking)
    
    /// Send a notification without waiting for response (fire and forget)
    public func sendAsync(_ config: NotifiCLIConfig) {
        Task.detached { [self] in
            _ = await self.send(config)
        }
    }
    
    /// Send a simple notification without waiting for response
    public func notify(title: String, message: String, sound: NotifiCLISound? = nil) {
        let config = NotifiCLIConfig(
            title: title,
            message: message,
            sound: sound?.rawValue,
            persistent: false
        )
        sendAsync(config)
    }
}

// MARK: - Errors

enum NotifiCLIError: LocalizedError {
    case sourceNotFound
    case compilationFailed(String)
    case setupFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .sourceNotFound:
            return "NotifiCLI source code not found in bundle"
        case .compilationFailed(let error):
            return "Failed to compile NotifiCLI: \(error)"
        case .setupFailed(let error):
            return "NotifiCLI setup failed: \(error)"
        }
    }
}

// MARK: - Embedded Source Code

extension NotifiCLIService {
    /// Embedded NotifiCLI source code (fallback if not bundled as resource)
    static let embeddedNotifiCLISource = """
import Foundation
import UserNotifications
import AppKit

var title: String?
var subtitle: String?
var message: String?
var actions: [String] = []
var imagePath: String?
var soundName: String?
var replyPlaceholder: String?
var openUrl: String?

var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    switch arg {
    case "-title": title = args.popFirst()
    case "-subtitle": subtitle = args.popFirst()
    case "-message": message = args.popFirst()
    case "-actions":
        if let actionStr = args.popFirst() {
            actions = actionStr.split(separator: ",").map { String($0) }
        }
    case "-image": imagePath = args.popFirst()
    case "-sound": soundName = args.popFirst()
    case "-reply": replyPlaceholder = args.popFirst()
    case "-url": openUrl = args.popFirst()
    default: break
    }
}

guard let notificationTitle = title, let notificationMessage = message else {
    print("Usage: notificli -title \\"Title\\" -message \\"Message\\" [-actions \\"A,B\\"]")
    exit(1)
}

let center = UNUserNotificationCenter.current()

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var selectedAction: String?
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let textResponse = response as? UNTextInputNotificationResponse {
            selectedAction = textResponse.userText
        } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            selectedAction = "default"
            if let openUrl = openUrl, let url = URL(string: openUrl) {
                NSWorkspace.shared.open(url)
            }
        } else if response.actionIdentifier == UNNotificationDismissActionIdentifier {
            selectedAction = "dismissed"
        } else {
            selectedAction = response.actionIdentifier
        }
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        var options: UNNotificationPresentationOptions = [.banner]
        if notification.request.content.sound != nil { options.insert(.sound) }
        completionHandler(options)
    }
}

let delegate = NotificationDelegate()
center.delegate = delegate

center.requestAuthorization(options: [.alert, .sound]) { _, error in
    if let error = error { print("Error: \\(error.localizedDescription)") }
}

var notificationActions: [UNNotificationAction] = []

if let replyPlaceholder = replyPlaceholder {
    let replyAction = UNTextInputNotificationAction(
        identifier: "REPLY_ACTION", title: "Reply", options: [.foreground],
        textInputButtonTitle: "Send", textInputPlaceholder: replyPlaceholder)
    notificationActions.append(replyAction)
}

if !actions.isEmpty {
    notificationActions.append(contentsOf: actions.map {
        UNNotificationAction(identifier: $0, title: $0, options: [])
    })
}

if !notificationActions.isEmpty {
    let category = UNNotificationCategory(identifier: "ACTIONS_CATEGORY",
                                           actions: notificationActions,
                                           intentIdentifiers: [], options: [.customDismissAction])
    let sem = DispatchSemaphore(value: 0)
    center.setNotificationCategories([category])
    center.getNotificationCategories { _ in sem.signal() }
    _ = sem.wait(timeout: .now() + 1.0)
}

let content = UNMutableNotificationContent()
content.title = notificationTitle
if let s = subtitle { content.subtitle = s }
content.body = notificationMessage
content.sound = nil
if !notificationActions.isEmpty { content.categoryIdentifier = "ACTIONS_CATEGORY" }

if let path = imagePath, (path.lowercased().hasPrefix("http://") || path.lowercased().hasPrefix("https://")),
   let url = URL(string: path) {
    let tempDir = URL(fileURLWithPath: "/tmp/notificli")
    do {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dest = tempDir.appendingPathComponent(url.lastPathComponent.isEmpty ? UUID().uuidString : url.lastPathComponent)
        
        let sem = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            if let data = data {
                try? data.write(to: dest)
                imagePath = dest.path
            }
            sem.signal()
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 30.0)
    } catch {}
}

if let imagePath = imagePath, FileManager.default.fileExists(atPath: imagePath) {
    let imageURL = URL(fileURLWithPath: imagePath)
    do {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + imageURL.pathExtension)
        try FileManager.default.copyItem(at: imageURL, to: temp)
        let attachment = try UNNotificationAttachment(identifier: "image", url: temp, options: nil)
        content.attachments = [attachment]
    } catch {}
}

let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
let sem = DispatchSemaphore(value: 0)
center.add(request) { error in
    if let error = error { print("Error: \\(error.localizedDescription)"); exit(1) }
    sem.signal()
}
_ = sem.wait(timeout: .now() + 2.0)

if let soundName = soundName {
    if let sound = NSSound(named: NSSound.Name((soundName as NSString).deletingPathExtension)) {
        sound.play()
        Thread.sleep(forTimeInterval: 1.0)
    }
}

if !actions.isEmpty || replyPlaceholder != nil || openUrl != nil {
    let deadline = Date().addingTimeInterval(60)
    while delegate.selectedAction == nil && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
    }
    if let action = delegate.selectedAction { print(action) }
}
"""
}
