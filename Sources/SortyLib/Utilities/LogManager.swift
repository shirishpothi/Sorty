//
//  LogManager.swift
//  Sorty
//
//  Production-grade logging system with rotation, sanitization, and export.
//

import Foundation

public enum DiagnosticReportError: LocalizedError {
    case unavailable
    case archiveFailed

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Sorty couldn't prepare the diagnostic report."
        case .archiveFailed:
            return "Sorty couldn't create the diagnostic ZIP archive."
        }
    }
}

public struct DiagnosticReportResult: Sendable {
    public let reportID: String
    public let sentryEventID: String?
}

public final class LogManager: @unchecked Sendable {
    public static let shared = LogManager()
    
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.sorty.logQueue")
    private let maxArchivedLogFiles = 2
    private let maxLogSize: UInt64 = 2 * 1024 * 1024
    private var currentLogSize: UInt64 = 0
    private var logFileHandle: FileHandle?
    private let timestampFormatter = ISO8601DateFormatter()
    private let userPathRegex = try? NSRegularExpression(pattern: "/Users/([^/]+)")
    
    private var logsDirectory: URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.sorty.app"
        let logsDir = appSupport.appendingPathComponent(bundleID).appendingPathComponent("Logs")
        
        if !fileManager.fileExists(atPath: logsDir.path) {
            try? fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
        }
        
        return logsDir
    }
    
    private var currentLogFile: URL? {
        return logsDirectory?.appendingPathComponent("sorty.log")
    }
    
    private init() {
        rotateLogsIfNeeded()
        if let logFile = currentLogFile,
           let size = try? logFile.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            currentLogSize = UInt64(size)
        }
    }
    
    // MARK: - Public API
    
    public func log(
        _ message: @autoclosure () -> String,
        level: LogLevel = .info,
        category: String = "General",
        data: [String: Any]? = nil
    ) {
        guard shouldPersist(level) else { return }
        let resolvedMessage = message()

        queue.async {
            self.writeLog(resolvedMessage, level: level, category: category, data: data)
        }
    }
    
    @MainActor
    public func generateDiagnosticReport(
        config: AIConfig,
        at destinationURL: URL
    ) throws -> DiagnosticReportResult {
        guard let logsDirectory else { throw DiagnosticReportError.unavailable }
        queue.sync {
            try? logFileHandle?.synchronize()
        }
        let reportID = UUID().uuidString.lowercased()
        let sentryEventID = ReliabilityManager.shared.captureDiagnosticReport(reportID: reportID)

        let reportDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("Sorty-Diagnostic-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: reportDirectory) }

        do {
            try fileManager.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
            try diagnosticOverview(
                config: config,
                reportID: reportID,
                sentryEventID: sentryEventID
            ).write(
                to: reportDirectory.appendingPathComponent("diagnostic.txt"),
                atomically: true,
                encoding: .utf8
            )
            try telemetryReport(reportID: reportID, sentryEventID: sentryEventID).write(
                to: reportDirectory.appendingPathComponent("telemetry.json"),
                atomically: true,
                encoding: .utf8
            )
            try logSummary(in: logsDirectory).write(
                to: reportDirectory.appendingPathComponent("log-summary.json"),
                atomically: true,
                encoding: .utf8
            )
            try safeLogTimeline(in: logsDirectory).write(
                to: reportDirectory.appendingPathComponent("log-timeline.json"),
                atomically: true,
                encoding: .utf8
            )
            try privacyReadme.write(
                to: reportDirectory.appendingPathComponent("README.txt"),
                atomically: true,
                encoding: .utf8
            )

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = [
                "-c", "-k", "--sequesterRsrc",
                reportDirectory.path, destinationURL.path,
            ]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw DiagnosticReportError.archiveFailed
            }
            return DiagnosticReportResult(
                reportID: reportID,
                sentryEventID: sentryEventID
            )
        } catch {
            if let reportError = error as? DiagnosticReportError {
                throw reportError
            }
            throw DiagnosticReportError.unavailable
        }
    }

    @MainActor
    private func diagnosticOverview(
        config: AIConfig,
        reportID: String,
        sentryEventID: String?
    ) -> String {
        let process = ProcessInfo.processInfo
        let defaults = UserDefaults.standard
        let memory = ByteCountFormatter.string(
            fromByteCount: Int64(process.physicalMemory),
            countStyle: .memory
        )
        return """
        Sorty Diagnostic Report
        Generated: \(timestampFormatter.string(from: Date()))
        Diagnostic ID: \(reportID)
        Sentry event: \(sentryEventID ?? "Not sent — reliability sharing is unavailable or disabled")

        App
        - Version: \(BuildInfo.fullVersion)
        - Commit: \(BuildInfo.shortCommit)
        - Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")

        System
        - macOS: \(process.operatingSystemVersionString)
        - Architecture: \(Self.systemArchitecture)
        - CPU cores: \(process.activeProcessorCount)
        - Memory: \(memory)
        - Locale: \(Locale.current.identifier)

        AI configuration
        - Provider: \(config.provider.displayName)
        - Model family: \(config.model.isEmpty ? "provider default" : "custom selection")
        - Auth method: \(config.authMethod(for: config.provider).displayName)
        - Custom API URL configured: \(Self.yesNo(config.apiURL?.isEmpty == false))
        - Mode: \(config.mode.displayName)
        - Deep scan: \(Self.yesNo(config.enableDeepScan))
        - Vision: \(Self.yesNo(config.enableVision))
        - Smart rename: \(Self.yesNo(config.enableSmartRename))
        - Duplicate detection: \(Self.yesNo(config.detectDuplicates))
        - File tagging: \(Self.yesNo(config.enableFileTagging))
        - Streaming: \(Self.yesNo(config.enableStreaming))
        - Reasoning: \(Self.yesNo(config.enableReasoning))
        - Request timeout: \(Int(config.requestTimeout))s
        - Resource timeout: \(Int(config.resourceTimeout))s

        App settings
        - Privacy mode: \(Self.yesNo(defaults.bool(forKey: "privacyModeEnabled")))
        - Block Internet Connections: \(Self.yesNo(FeatureFlags.internetPrivacyModeEnabled))
        - Menu bar extra: \(Self.yesNo(defaults.object(forKey: "showMenuBarExtra") as? Bool ?? true))
        - Completed onboarding: \(Self.yesNo(defaults.bool(forKey: "hasCompletedOnboarding")))
        """
    }

    @MainActor
    private func telemetryReport(reportID: String, sentryEventID: String?) throws -> String {
        let analytics = AnalyticsManager.shared
        let reliability = ReliabilityManager.shared
        let activityCounts = Dictionary(
            grouping: NotificationManager.shared.analyticsEvents,
            by: { "\($0.eventType.rawValue):\($0.notificationType)" }
        ).mapValues(\.count)

        let report: [String: Any] = [
            "diagnostic_report_id": reportID,
            "sentry_event_id": sentryEventID ?? NSNull(),
            "posthog": [
                "consent": analytics.consent.rawValue,
                "active": analytics.isActive,
                "person_profiles": "disabled",
                "geoip": "disabled",
                "allowed_event_families": [
                    "app:session_started",
                    "app:screen_viewed",
                    "app:feature_used",
                    "app:workflow_progressed",
                    "app:important_button_clicked",
                ],
                "active_experiment_count": analytics.experimentalFeatures.count,
            ],
            "sentry": reliability.diagnosticSummary,
            "local_activity_counts": activityCounts,
            "privacy": [
                "contains_remote_events": false,
                "contains_user_or_device_ids": false,
                "contains_diagnostic_correlation_ids": true,
                "contains_raw_errors": false,
                "contains_notification_details": false,
            ],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys]
        )
        return String(decoding: data, as: UTF8.self)
    }

    private func safeLogTimeline(in directory: URL) throws -> String {
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "log" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let pattern = try NSRegularExpression(
            pattern: #"^\[([^\]]+)\] \[([A-Z]+)\] \[([A-Za-z0-9_. -]{1,64})\] (.*)$"#
        )
        var entries: [[String: String]] = []

        for file in files {
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }
            contents.enumerateLines { line, _ in
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                guard let match = pattern.firstMatch(in: line, range: range),
                      let timestampRange = Range(match.range(at: 1), in: line),
                      let levelRange = Range(match.range(at: 2), in: line),
                      let categoryRange = Range(match.range(at: 3), in: line),
                      let messageRange = Range(match.range(at: 4), in: line)
                else { return }
                let signals = Self.diagnosticSignals(in: String(line[messageRange]))
                entries.append([
                    "timestamp": String(line[timestampRange]),
                    "level": String(line[levelRange]),
                    "category": String(line[categoryRange]),
                    "signals": signals.isEmpty ? "none" : signals.joined(separator: ","),
                ])
                if entries.count > 250 {
                    entries.removeFirst(entries.count - 250)
                }
            }
        }

        let data = try JSONSerialization.data(
            withJSONObject: [
                "entries": entries,
                "raw_messages_included": false,
                "description": "Chronology and machine-derived failure signals; message text is discarded.",
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
        return String(decoding: data, as: UTF8.self)
    }

    private static func diagnosticSignals(in message: String) -> [String] {
        let lowercased = message.lowercased()
        var signals: [String] = []
        let rules: [(String, [String])] = [
            ("timeout", ["timeout", "timed out"]),
            ("cancelled", ["cancelled", "canceled"]),
            ("permission_denied", ["permission", "not permitted", "access denied"]),
            ("authentication", ["unauthorized", "authentication", "invalid token", "signing out"]),
            ("rate_limited", ["rate limit", "too many requests"]),
            ("network", ["connection", "network", "offline", "dns"]),
            ("file_conflict", ["already exists", "path exists", "conflict"]),
            ("parse_failure", ["parse", "decoding", "invalid json"]),
        ]
        for (signal, needles) in rules where needles.contains(where: lowercased.contains) {
            signals.append(signal)
        }
        if let status = firstMatch(in: message, pattern: #"\bHTTP\s+([1-5][0-9]{2})\b"#) {
            signals.append("http_\(status)")
        }
        if let exitCode = firstMatch(in: message, pattern: #"\bexit(?:ed)?\s*(?:code|status)?[: ]+(-?[0-9]+)\b"#) {
            signals.append("exit_\(exitCode)")
        }
        return signals
    }

    private static func firstMatch(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                  in: value,
                  range: NSRange(value.startIndex..<value.endIndex, in: value)
              ),
              let range = Range(match.range(at: 1), in: value)
        else {
            return nil
        }
        return String(value[range])
    }

    private func logSummary(in directory: URL) throws -> String {
        var levels: [String: Int] = [:]
        var categories: [String: Int] = [:]
        let pattern = try NSRegularExpression(
            pattern: #"^\[[^\]]+\] \[([A-Z]+)\] \[([A-Za-z0-9_. -]{1,64})\]"#
        )
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "log" }

        for file in files {
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }
            contents.enumerateLines { line, _ in
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                guard let match = pattern.firstMatch(in: line, range: range),
                      let levelRange = Range(match.range(at: 1), in: line),
                      let categoryRange = Range(match.range(at: 2), in: line)
                else { return }
                levels[String(line[levelRange]), default: 0] += 1
                categories[String(line[categoryRange]), default: 0] += 1
            }
        }

        let report: [String: Any] = [
            "log_file_count": files.count,
            "levels": levels,
            "categories": categories,
            "raw_messages_included": false,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys]
        )
        return String(decoding: data, as: UTF8.self)
    }

    private var privacyReadme: String {
        """
        This archive is designed to be safe to attach to a public GitHub issue.

        It intentionally excludes raw log messages, file and folder names, paths,
        file contents, prompts, AI responses, credentials, API URLs, email
        addresses, user or device identifiers, PostHog event payloads, Sentry
        envelopes, crash dumps, and SDK caches. The diagnostic and Sentry event
        IDs are random correlation values and do not identify the user or device.

        diagnostic.txt contains environment and bounded configuration facts.
        telemetry.json describes analytics and reliability status plus aggregate
        local activity categories. log-summary.json contains counts only.
        log-timeline.json preserves chronology and recognized failure signals
        while permanently discarding every raw log message.
        """
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private static var systemArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
    
    // MARK: - Private Methods
    
    private func writeLog(_ message: String, level: LogLevel, category: String, data: [String: Any]?) {
        guard let logFile = currentLogFile else { return }
        
        let timestamp = timestampFormatter.string(from: Date())
        let sanitizedMessage = sanitize(message)
        var contextString = ""
        
        if let data = data {
            if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                contextString = " | Context: " + sanitize(jsonString)
            }
        }
        
        let logLine = "[\(timestamp)] [\(level.rawValue.uppercased())] [\(category)] \(sanitizedMessage)\(contextString)\n"
        
        guard let data = logLine.data(using: .utf8) else { return }

        if logFileHandle == nil {
            if !fileManager.fileExists(atPath: logFile.path) {
                fileManager.createFile(atPath: logFile.path, contents: nil)
            }
            logFileHandle = try? FileHandle(forWritingTo: logFile)
            try? logFileHandle?.seekToEnd()
        }

        guard let logFileHandle else { return }

        do {
            try logFileHandle.write(contentsOf: data)
            currentLogSize += UInt64(data.count)
            if level >= .warning {
                try logFileHandle.synchronize()
            }
        } catch {
            try? logFileHandle.close()
            self.logFileHandle = nil
        }

        if currentLogSize > maxLogSize {
            rotateLogsIfNeeded(force: true)
        }
    }

    private func shouldPersist(_ level: LogLevel) -> Bool {
#if DEBUG
        level >= .debug
#else
        level >= .info
#endif
    }

    private func sanitize(_ text: String) -> String {
        var result = text
        
        // Redact standard API keys
        result = result.replacingOccurrences(of: "sk-[a-zA-Z0-9]{20,}", with: "[REDACTED_OPENAI_KEY]", options: .regularExpression)
        result = result.replacingOccurrences(of: "ghp_[a-zA-Z0-9]{20,}", with: "[REDACTED_GITHUB_TOKEN]", options: .regularExpression)
        result = result.replacingOccurrences(of: "gho_[a-zA-Z0-9]{20,}", with: "[REDACTED_GITHUB_TOKEN]", options: .regularExpression)
        
        // Redact User Paths
        // Matches /Users/username/ or /Users/username
        // We look for /Users/ followed by non-slash characters
        if let regex = userPathRegex {
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            
            // Iterate in reverse to avoid range offsets shifting
            for match in matches.reversed() {
                if match.numberOfRanges > 1 {
                    let usernameRange = match.range(at: 1)
                    let username = nsString.substring(with: usernameRange)
                    
                    // Don't redact "Shared" or "Guest" if desired, but for strict privacy, redact all users
                    if username != "Shared" {
                        result = result.replacingOccurrences(of: "/Users/\(username)", with: "/Users/[REDACTED_USER]")
                    }
                }
            }
        }
        
        return result
    }
    
    private func rotateLogsIfNeeded(force: Bool = false) {
        guard let logsDirectory = logsDirectory, let currentLog = currentLogFile else { return }
        
        // If current log exists and is too big, or if we just want to verify cleanup
        if force || (try? fileManager.attributesOfItem(atPath: currentLog.path)) != nil {
            if force {
                try? logFileHandle?.close()
                logFileHandle = nil

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let timestamp = formatter.string(from: Date())
                let archivedLog = logsDirectory.appendingPathComponent("sorty-\(timestamp).log")
                
                try? fileManager.moveItem(at: currentLog, to: archivedLog)
                currentLogSize = 0
            }
            
            // Cleanup old logs
            do {
                let fileURLs = try fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
                let logFiles = fileURLs.filter {
                    $0.pathExtension == "log" && $0 != currentLog
                }
                
                if logFiles.count > maxArchivedLogFiles {
                    let sortedFiles = logFiles.sorted {
                        let date0 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                        let date1 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                        return date0 < date1
                    }
                    
                    // Delete oldest
                    for i in 0..<(sortedFiles.count - maxArchivedLogFiles) {
                        try? fileManager.removeItem(at: sortedFiles[i])
                    }
                }
            } catch {
                print("Error rotating logs: \(error)")
            }
        }
    }
}

public enum LogLevel: String, Comparable {
    case debug
    case info
    case warning
    case error
    case fault

    private var priority: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .warning: 2
        case .error: 3
        case .fault: 4
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.priority < rhs.priority
    }
}
