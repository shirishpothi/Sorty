//
//  AnalyticsManager.swift
//  Sorty
//
//  Consent-gated, privacy-preserving product and reliability analytics.
//

import Combine
import Foundation
import PostHog

public enum AnalyticsConsent: String, Sendable {
    case undecided
    case granted
    case denied
}

@MainActor
public final class AnalyticsManager: ObservableObject {
    public static let shared = AnalyticsManager()

    public static let consentDefaultsKey = "analyticsConsent"
    private static let crashCollectionSuspendedDefaultsKey =
        "analyticsCrashCollectionSuspended"

    @Published public private(set) var consent: AnalyticsConsent
    @Published public private(set) var isActive = false

    private let defaults: UserDefaults
    private var activeProjectToken: String?

    private static let productionProjectToken = "phc_rhKqvGRtWWMrSEC34WwUJipMZYM8kJA9ppav4ZxK7RiB"
    private static let productionHost = "https://us.i.posthog.com"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        consent = defaults.string(forKey: Self.consentDefaultsKey)
            .flatMap(AnalyticsConsent.init(rawValue:)) ?? .undecided
    }

    public func startIfAuthorized() {
        guard consent == .granted,
              !NetworkPrivacyPolicy.isInternetPrivacyModeEnabled,
              !Self.isAnalyticsSuppressedForThisProcess,
              !isActive
        else {
            if defaults.bool(forKey: Self.crashCollectionSuspendedDefaultsKey) {
                Self.removePendingCrashReport()
            }
            return
        }

        if defaults.bool(forKey: Self.crashCollectionSuspendedDefaultsKey) {
            Self.removePendingCrashReport()
            defaults.set(false, forKey: Self.crashCollectionSuspendedDefaultsKey)
        }

        let environment = ProcessInfo.processInfo.environment
        let projectToken = environment["SORTY_POSTHOG_PROJECT_TOKEN"] ?? Self.productionProjectToken
        let host = environment["SORTY_POSTHOG_HOST"] ?? Self.productionHost
        guard !projectToken.isEmpty else { return }

        let config = PostHogConfig(projectToken: projectToken, host: host)
        config.personProfiles = .never
        config.setDefaultPersonProperties = false
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.enableSwizzling = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.flushAt = 20
        config.maxQueueSize = 250
        config.errorTrackingConfig.autoCapture = true
        config.errorTrackingConfig.inAppIncludes = ["Sorty", "SortyLib"]
        config.errorTrackingConfig.inAppByDefault = false
        config.errorTrackingConfig.exceptionSteps.enabled = false
        config.setBeforeSend { event in
            Self.sanitized(event: event)
        }

        PostHogSDK.shared.setup(config)
        activeProjectToken = projectToken
        isActive = true
        capture(
            event: "app:session_started",
            properties: [
                "platform_surface": "mac_app",
                "launch_source": "standard",
            ]
        )
    }

    public func setConsent(_ newConsent: AnalyticsConsent) {
        guard newConsent != .undecided else { return }

        defaults.set(newConsent.rawValue, forKey: Self.consentDefaultsKey)
        consent = newConsent

        switch newConsent {
        case .granted:
            startIfAuthorized()
            captureFeature(
                feature: "privacy",
                subfeature: "analytics",
                action: "enabled",
                outcome: "success"
            )
        case .denied:
            stopAndClear()
        case .undecided:
            break
        }
    }

    public func networkPrivacyDidChange(isEnabled: Bool) {
        if isEnabled {
            stopAndClear()
        } else {
            startIfAuthorized()
        }
    }

    public func resetConsentAndData() {
        stopAndClear()
        defaults.removeObject(forKey: Self.consentDefaultsKey)
        consent = .undecided
    }

    public func captureScreen(
        _ screen: String,
        section: String? = nil,
        source: String = "navigation"
    ) {
        var properties: [String: Any] = [
            "screen": screen,
            "source": source,
        ]
        properties["section"] = section
        capture(event: "app:screen_viewed", properties: properties)
    }

    public func captureFeature(
        feature: String,
        subfeature: String,
        action: String,
        outcome: String,
        properties: [String: Any] = [:]
    ) {
        capture(
            event: "app:feature_used",
            properties: properties.merging([
                "feature": feature,
                "subfeature": subfeature,
                "action": action,
                "outcome": outcome,
            ]) { current, _ in current }
        )
    }

    public func captureWorkflow(
        workflow: String,
        stage: String,
        outcome: String,
        properties: [String: Any] = [:]
    ) {
        capture(
            event: "app:workflow_progressed",
            properties: properties.merging([
                "workflow": workflow,
                "stage": stage,
                "outcome": outcome,
            ]) { current, _ in current }
        )
    }

    public func captureImportantButton(
        _ button: String,
        screen: String,
        feature: String
    ) {
        capture(
            event: "app:important_button_clicked",
            properties: [
                "button": button,
                "screen": screen,
                "feature": feature,
            ]
        )
    }

    public func captureSettingChanged(
        _ control: String,
        isEnabled: Bool,
        section: String = "settings"
    ) {
        captureFeature(
            feature: "settings",
            subfeature: section,
            action: "toggle_changed",
            outcome: isEnabled ? "enabled" : "disabled",
            properties: ["control": control]
        )
    }

    public func capturePersonaInventory(
        action: String,
        customPersonaCount: Int,
        selectionKind: String? = nil
    ) {
        var properties: [String: Any] = [
            "count_bucket": Self.countBucket(customPersonaCount),
        ]
        properties["selection_kind"] = selectionKind
        captureFeature(
            feature: "personas",
            subfeature: "custom_personas",
            action: action,
            outcome: "success",
            properties: properties
        )
    }

    public func capture(
        error: Error,
        feature: String,
        operation: String,
        severity: String = "error",
        recoverable: Bool = true
    ) {
        guard canCapture else { return }

        let classification = Self.classify(error)
        let sanitizedError = SanitizedAnalyticsError(
            category: classification.category,
            cause: classification.cause,
            operation: operation
        )

        PostHogSDK.shared.captureException(
            sanitizedError,
            properties: [
                "platform_surface": "mac_app",
                "feature": feature,
                "operation": operation,
                "error_category": classification.category,
                "error_cause": classification.cause,
                "error_type": classification.type,
                "severity": severity,
                "recoverable": recoverable,
                "$geoip_disable": true,
            ]
        )
    }

    public static func countBucket(_ count: Int) -> String {
        switch count {
        case ..<1: return "0"
        case 1: return "1"
        case 2...5: return "2_5"
        case 6...20: return "6_20"
        case 21...100: return "21_100"
        default: return "101_plus"
        }
    }

    public static func durationBucket(_ duration: TimeInterval) -> String {
        switch duration {
        case ..<1: return "under_1s"
        case ..<5: return "1_5s"
        case ..<15: return "5_15s"
        case ..<60: return "15_60s"
        case ..<300: return "1_5m"
        default: return "5m_plus"
        }
    }

    private var canCapture: Bool {
        isActive
            && consent == .granted
            && !NetworkPrivacyPolicy.isInternetPrivacyModeEnabled
            && !Self.isAnalyticsSuppressedForThisProcess
    }

    private func capture(event: String, properties: [String: Any]) {
        guard canCapture else { return }
        var safeProperties = properties
        safeProperties["platform_surface"] = "mac_app"
        safeProperties["$geoip_disable"] = true
        PostHogSDK.shared.capture(event, properties: safeProperties)
    }

    private func stopAndClear() {
        defaults.set(true, forKey: Self.crashCollectionSuspendedDefaultsKey)

        let environment = ProcessInfo.processInfo.environment
        let projectToken = activeProjectToken
            ?? environment["SORTY_POSTHOG_PROJECT_TOKEN"]
            ?? Self.productionProjectToken

        if isActive {
            isActive = false
            PostHogSDK.shared.close()
        }

        Self.removePersistedSDKData(projectToken: projectToken)
        Self.removePendingCrashReport()
        activeProjectToken = nil
    }

    private nonisolated static func removePersistedSDKData(projectToken: String) {
        let isSafePathComponent = !projectToken.isEmpty && projectToken.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-"
        }
        guard isSafePathComponent,
              let applicationSupport = FileManager.default.urls(
                  for: .applicationSupportDirectory,
                  in: .userDomainMask
              ).first
        else {
            return
        }

        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.sorty.app"
        let sdkDirectory = applicationSupport
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent(projectToken, isDirectory: true)
        try? FileManager.default.removeItem(at: sdkDirectory)
    }

    private nonisolated static func removePendingCrashReport() {
        guard let cachesDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first
        else {
            return
        }

        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.sorty.app"
        let crashReportDirectory = cachesDirectory
            .appendingPathComponent(
                "com.plausiblelabs.crashreporter.data",
                isDirectory: true
            )
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
        try? FileManager.default.removeItem(at: crashReportDirectory)
    }

    private nonisolated static var isAnalyticsSuppressedForThisProcess: Bool {
        let process = ProcessInfo.processInfo
        return process.environment["XCTestConfigurationFilePath"] != nil
            || process.arguments.contains("--uitesting")
            || process.environment["SORTY_HARNESS_MODE"] == "1"
    }

    private nonisolated static func sanitized(event: PostHogEvent) -> PostHogEvent? {
        let allowedEvents: Set<String> = [
            "app:session_started",
            "app:screen_viewed",
            "app:feature_used",
            "app:workflow_progressed",
            "app:important_button_clicked",
            "$exception",
        ]
        guard allowedEvents.contains(event.event) else { return nil }

        let allowedProperties: Set<String> = [
            "$app_build",
            "$app_version",
            "$debug_images",
            "$device_type",
            "$geoip_disable",
            "$lib",
            "$lib_version",
            "$os_name",
            "$os_version",
            "$process_person_profile",
            "$session_id",
            "action",
            "button",
            "control",
            "count_bucket",
            "duration_bucket",
            "entry_source",
            "error_category",
            "error_cause",
            "error_type",
            "feature",
            "has_custom_instructions",
            "launch_source",
            "mode",
            "operation",
            "outcome",
            "platform_surface",
            "recoverable",
            "result_kind",
            "screen",
            "section",
            "selection_kind",
            "semantic_enabled",
            "severity",
            "source",
            "stage",
            "subfeature",
            "variant",
            "workflow",
        ]

        let originalProperties = event.properties
        var safeProperties = originalProperties.reduce(into: [String: Any]()) { result, pair in
            guard allowedProperties.contains(pair.key) || pair.key.hasPrefix("$exception") else {
                return
            }
            result[pair.key] = pair.key == "$debug_images"
                ? sanitizedExceptionData(pair.value)
                : sanitized(value: pair.value)
        }

        if event.event == "$exception" {
            if let exceptionList = originalProperties["$exception_list"] {
                safeProperties["$exception_list"] = sanitizedExceptionData(exceptionList)
            }

            if originalProperties["$exception_level"] as? String == "fatal" {
                let crash = crashClassification(from: originalProperties)
                safeProperties["feature"] = "app_runtime"
                safeProperties["operation"] = "process_crash"
                safeProperties["error_category"] = "crash"
                safeProperties["error_cause"] = crash.cause
                safeProperties["error_type"] = crash.type
                safeProperties["severity"] = "fatal"
                safeProperties["recoverable"] = false
            }
        }

        safeProperties["$geoip_disable"] = true
        safeProperties["platform_surface"] = "mac_app"
        event.properties = safeProperties
        return event
    }

    private nonisolated static func sanitizedExceptionData(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, pair in
                if ["value", "message", "crash_info_message"].contains(pair.key),
                   pair.value is String
                {
                    result[pair.key] = "[redacted]"
                } else if ["abs_path", "code_file", "filename"].contains(pair.key),
                          let path = pair.value as? String
                {
                    result[pair.key] = safeFileComponent(path)
                } else {
                    result[pair.key] = sanitizedExceptionData(pair.value)
                }
            }
        }
        if let array = value as? [Any] {
            return array.map(sanitizedExceptionData)
        }
        return sanitized(value: value)
    }

    private nonisolated static func safeFileComponent(_ path: String) -> String {
        let component: String
        if let url = URL(string: path), url.scheme != nil {
            component = url.lastPathComponent
        } else {
            component = URL(fileURLWithPath: path).lastPathComponent
        }
        return sanitized(string: String(component.prefix(128)))
    }

    private nonisolated static func crashClassification(
        from properties: [String: Any]
    ) -> ErrorClassification {
        let exception = (properties["$exception_list"] as? [[String: Any]])?.first
        let rawType = exception?["type"] as? String ?? "native_crash"
        let mechanism = (exception?["mechanism"] as? [String: Any])?["type"] as? String

        let cause: String
        switch mechanism {
        case "nsexception":
            cause = "uncaught_exception"
        case "signal":
            cause = "fatal_signal"
        case "mach_exception":
            cause = "mach_exception"
        default:
            cause = "process_crash"
        }

        return ErrorClassification(
            category: "crash",
            cause: cause,
            type: boundedIdentifier(rawType, fallback: "native_crash")
        )
    }

    private nonisolated static func boundedIdentifier(
        _ value: String,
        fallback: String
    ) -> String {
        let normalized = value.lowercased().replacingOccurrences(
            of: #"[^a-z0-9_.-]+"#,
            with: "_",
            options: .regularExpression
        )
        let bounded = String(normalized.prefix(64))
        return bounded.isEmpty ? fallback : bounded
    }

    private nonisolated static func sanitized(value: Any) -> Any {
        if let string = value as? String {
            return sanitized(string: string)
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.mapValues(sanitized(value:))
        }
        if let array = value as? [Any] {
            return array.map(sanitized(value:))
        }
        return value
    }

    private nonisolated static func sanitized(string: String) -> String {
        var result = String(string.prefix(500))
        result = result.replacingOccurrences(
            of: #"file://[^\s]+"#,
            with: "file://[redacted]",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"/Users/[^/\s]+(?:/[^\s]*)?"#,
            with: "/Users/[redacted]",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?<![A-Za-z0-9:])/(?:[^\s/]+/)*[^\s/]+"#,
            with: "/[redacted-path]",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            with: "[redacted-email]",
            options: [.regularExpression, .caseInsensitive]
        )
        return result
    }

    private nonisolated static func classify(_ error: Error) -> ErrorClassification {
        let nsError = error as NSError
        let description = nsError.localizedDescription.lowercased()

        if error is CancellationError
            || nsError.code == NSUserCancelledError
            || nsError.code == NSURLErrorCancelled
            || description.contains("cancelled")
            || description.contains("canceled")
        {
            return ErrorClassification(category: "cancellation", cause: "user_or_system_cancelled", type: "cancelled")
        }
        if nsError.code == NSURLErrorTimedOut || description.contains("timed out") || description.contains("timeout") {
            return ErrorClassification(category: "network", cause: "timeout", type: "url_error")
        }
        if nsError.domain == NSURLErrorDomain {
            return ErrorClassification(category: "network", cause: "connection_failed", type: "url_error")
        }
        if nsError.domain == NSPOSIXErrorDomain || nsError.domain == NSCocoaErrorDomain {
            if description.contains("permission") || description.contains("not permitted") || description.contains("access") {
                return ErrorClassification(category: "permission", cause: "access_denied", type: "filesystem_error")
            }
            return ErrorClassification(category: "filesystem", cause: "file_operation_failed", type: "filesystem_error")
        }
        if description.contains("block internet") || description.contains("internet connections") {
            return ErrorClassification(category: "privacy", cause: "network_blocked", type: "policy_error")
        }
        if description.contains("api key") || description.contains("authentication") || description.contains("unauthorized") {
            return ErrorClassification(category: "authentication", cause: "credentials_rejected", type: "provider_error")
        }
        if description.contains("configuration") || description.contains("not configured") {
            return ErrorClassification(category: "configuration", cause: "missing_or_invalid_configuration", type: "configuration_error")
        }
        if description.contains("validation") || description.contains("invalid response") || description.contains("decode") {
            return ErrorClassification(category: "validation", cause: "invalid_data", type: "validation_error")
        }

        return ErrorClassification(category: "unknown", cause: "unclassified", type: "application_error")
    }
}

private struct ErrorClassification: Sendable {
    let category: String
    let cause: String
    let type: String
}

private struct SanitizedAnalyticsError: LocalizedError, CustomNSError {
    let category: String
    let cause: String
    let operation: String

    static var errorDomain: String { "com.sorty.app.analytics" }
    var errorCode: Int { 1 }
    var errorDescription: String? { "\(category):\(cause):\(operation)" }
}
