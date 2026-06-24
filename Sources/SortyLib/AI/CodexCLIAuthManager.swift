//
//  CodexCLIAuthManager.swift
//  Sorty
//
//  Manages OpenAI authentication via Codex CLI (~/.codex/auth.json)
//

import Foundation
import AppKit

public struct CodexDeviceAuthSession: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case starting
        case waiting
        case authorized
        case failed(String)
    }

    public var verificationURL: URL?
    public var userCode: String?
    public var status: Status

    public init(verificationURL: URL? = nil, userCode: String? = nil, status: Status = .starting) {
        self.verificationURL = verificationURL
        self.userCode = userCode
        self.status = status
    }
}

@MainActor
public final class CodexCLIAuthManager: ObservableObject {
    @Published public var isAuthenticated = false
    @Published public var accountEmail: String?
    @Published public var authError: String?
    @Published public var isCodexInstalled = false
    @Published public var deviceAuthSession: CodexDeviceAuthSession?

    enum LoginStatus: Sendable, Equatable {
        case chatGPT
        case accessToken
        case apiKey
        case notLoggedIn(String?)
        case unavailable(String?)

        var isSubscriptionUsable: Bool {
            switch self {
            case .chatGPT, .accessToken:
                return true
            default:
                return false
            }
        }
    }

    private var authFilePath: String {
        Self.authFileURL.path
    }

    private var deviceAuthProcess: Process?
    private var deviceAuthOutput = ""

    private nonisolated static var codexHomeURL: URL {
        let environment = ProcessInfo.processInfo.environment
        if let codexHome = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !codexHome.isEmpty {
            return URL(fileURLWithPath: codexHome)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    private nonisolated static var authFileURL: URL {
        codexHomeURL.appendingPathComponent("auth.json")
    }

    private nonisolated static var configFileURL: URL {
        codexHomeURL.appendingPathComponent("config.toml")
    }

    struct CodexAuth: Codable {
        let auth_mode: String?
        let tokens: CodexTokens?
        let last_refresh: String?
    }

    struct CodexTokens: Codable {
        let id_token: String?
        let access_token: String?
        let refresh_token: String?
        let account_id: String?
    }

    public init() {
        checkStatus()
    }

    nonisolated static func hasUsableSubscriptionLogin() -> Bool {
        readLoginStatus().isSubscriptionUsable
    }

    nonisolated static func readLoginStatus() -> LoginStatus {
        if let codexExecutablePath = resolveCodexExecutablePath() {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: codexExecutablePath)
            process.arguments = ["login", "status"]

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            do {
                try process.run()
                process.waitUntilExit()

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if process.terminationStatus == 0 {
                    return parseLoginStatusOutput(output)
                }

                if let fallback = readFileBackedSubscriptionStatus() {
                    return fallback
                }

                return .notLoggedIn(output)
            } catch {
                if let fallback = readFileBackedSubscriptionStatus() {
                    return fallback
                }
                return .unavailable(error.localizedDescription)
            }
        }

        if let fallback = readFileBackedSubscriptionStatus() {
            return fallback
        }

        return .unavailable("Codex CLI not found. Install with: npm i -g @openai/codex")
    }

    nonisolated static func readConfiguredModel() -> String? {
        guard let configContents = readConfigFile() else {
            return nil
        }
        return readTomlStringValue(for: "model", in: configContents)
    }

    public func checkStatus() {
        Task { await refreshStatus() }
    }

    /// Refreshes the published auth state. The underlying Codex CLI probes shell
    /// out to a subprocess and block on `Process.waitUntilExit()`, which spins
    /// the run loop. That must never happen on the main thread, because during
    /// app launch / SwiftUI scene instantiation it re-enters the in-progress
    /// AttributeGraph transaction and aborts the app. So the blocking work is
    /// performed on a detached background task and only the resulting state is
    /// applied back on the main actor.
    public func refreshStatus() async {
        let installed = await Task.detached(priority: .userInitiated) {
            Self.resolveCodexExecutablePath() != nil
        }.value

        let status = await Task.detached(priority: .userInitiated) {
            Self.readLoginStatus()
        }.value

        isCodexInstalled = installed

        switch status {
        case .chatGPT, .accessToken:
            isAuthenticated = true
            accountEmail = extractEmail(from: Self.readIDToken())
            authError = nil
            markDeviceAuthAuthorizedIfNeeded()

        case .apiKey:
            isAuthenticated = false
            accountEmail = nil
            authError = "Codex CLI is signed in with an API key. Use ChatGPT sign-in or a Codex access token for subscription-backed inference."

        case .notLoggedIn:
            isAuthenticated = false
            accountEmail = nil
            authError = nil

        case .unavailable(let message):
            isAuthenticated = false
            accountEmail = nil
            authError = message
        }
    }

    func signOut() {
        if let codexExecutablePath = resolveCodexExecutablePath() {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: codexExecutablePath)
            process.arguments = ["logout"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // Fall through to local cache cleanup.
            }
        }

        do {
            try FileManager.default.removeItem(atPath: authFilePath)
        } catch {
            // File may not exist, that's fine
        }
        isAuthenticated = false
        accountEmail = nil
        authError = nil
    }

    func openTerminalWithLogin() {
        do {
            let scriptURL = try prepareLoginScript()
            guard NSWorkspace.shared.open(scriptURL) else {
                authError = "Could not open your default terminal app. Please run 'codex login' manually."
                return
            }
            authError = nil
        } catch {
            authError = "Could not open your default terminal app. Please run 'codex login' manually."
        }
    }

    func startDeviceAuth() {
        cancelDeviceAuth()

        guard let codexExecutablePath = resolveCodexExecutablePath() else {
            deviceAuthSession = CodexDeviceAuthSession(status: .failed("Codex CLI not found. Install with: npm i -g @openai/codex"))
            authError = "Codex CLI not found. Install with: npm i -g @openai/codex"
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexExecutablePath)
        process.arguments = ["login", "--device-auth"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        deviceAuthOutput = ""
        deviceAuthProcess = process
        deviceAuthSession = CodexDeviceAuthSession(status: .starting)
        authError = nil

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.consumeDeviceAuthOutput(chunk)
            }
        }

        process.terminationHandler = { [weak self, weak outputPipe] finishedProcess in
            outputPipe?.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in
                self?.completeDeviceAuthProcess(finishedProcess.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            deviceAuthProcess = nil
            let message = "Could not start Codex device authorization. Please run 'codex login --device-auth' manually."
            deviceAuthSession = CodexDeviceAuthSession(status: .failed(message))
            authError = message
        }
    }

    func cancelDeviceAuth() {
        deviceAuthProcess?.terminate()
        deviceAuthProcess = nil
        deviceAuthOutput = ""
        deviceAuthSession = nil
    }

    private func consumeDeviceAuthOutput(_ chunk: String) {
        deviceAuthOutput += Self.strippedANSIEscapeSequences(from: chunk)

        var session = deviceAuthSession ?? CodexDeviceAuthSession()
        if session.verificationURL == nil,
           let url = Self.firstURL(in: deviceAuthOutput) {
            session.verificationURL = url
        }
        if session.userCode == nil,
           let code = Self.firstDeviceCode(in: deviceAuthOutput) {
            session.userCode = code
        }
        if session.verificationURL != nil || session.userCode != nil {
            session.status = .waiting
        }
        deviceAuthSession = session
    }

    private func completeDeviceAuthProcess(_ terminationStatus: Int32) {
        deviceAuthProcess = nil
        checkStatus()

        if isAuthenticated {
            markDeviceAuthAuthorizedIfNeeded()
            return
        }

        guard terminationStatus != 15 else { return }

        let message = "Codex authorization did not complete. Try again or run 'codex login --device-auth' manually."
        deviceAuthSession = CodexDeviceAuthSession(
            verificationURL: deviceAuthSession?.verificationURL,
            userCode: deviceAuthSession?.userCode,
            status: .failed(message)
        )
        authError = message
    }

    private func markDeviceAuthAuthorizedIfNeeded() {
        guard let deviceAuthSession else { return }

        self.deviceAuthSession = CodexDeviceAuthSession(
            verificationURL: deviceAuthSession.verificationURL,
            userCode: deviceAuthSession.userCode,
            status: .authorized
        )
    }

    private func prepareLoginScript() throws -> URL {
        guard let codexExecutablePath = resolveCodexExecutablePath() else {
            throw NSError(
                domain: "CodexCLIAuthManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Codex CLI executable was not found"]
            )
        }
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sorty-codex-login.command")
        let script = """
        #!/bin/zsh
        \(Self.shellQuoted(codexExecutablePath)) login
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private nonisolated static func resolveCodexExecutablePath() -> String? {
        let paths = [
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/bin/codex",
        ]

        for path in paths where FileManager.default.fileExists(atPath: path) {
            return path
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "codex"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return nil
            }

            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let resolvedPath = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !resolvedPath.isEmpty,
                  FileManager.default.fileExists(atPath: resolvedPath) else {
                return nil
            }

            return resolvedPath
        } catch {
            return nil
        }
    }

    private func resolveCodexExecutablePath() -> String? {
        Self.resolveCodexExecutablePath()
    }

    nonisolated static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private nonisolated static func strippedANSIEscapeSequences(from string: String) -> String {
        string
            .replacingOccurrences(
                of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "\u{001B}\\][^\u{0007}]*(\u{0007}|\u{001B}\\\\)",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "\r",
                with: "\n"
            )
    }

    private nonisolated static func normalizedDeviceAuthOutput(_ string: String) -> String {
        string.replacingOccurrences(
            of: #"[^\S\r\n]+"#,
            with: "",
            options: .regularExpression
        )
    }

    private nonisolated static func firstURL(in string: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return detector.firstMatch(in: string, options: [], range: range)?.url
    }

    private nonisolated static func firstDeviceCode(in string: String) -> String? {
        let normalizedOutput = normalizedDeviceAuthOutput(string)
        let pattern = #"\b(?:[A-Z0-9]{4}(?:-[A-Z0-9]{4,6}){1,2}|[A-Z0-9]{8,12})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(normalizedOutput.startIndex..<normalizedOutput.endIndex, in: normalizedOutput)
        guard let match = regex.firstMatch(in: normalizedOutput, range: range),
              let codeRange = Range(match.range, in: normalizedOutput) else {
            return nil
        }
        return String(normalizedOutput[codeRange])
    }

    private func extractEmail(from idToken: String?) -> String? {
        guard let idToken else { return nil }
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Pad base64 to multiple of 4
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json["email"] as? String
    }

    private nonisolated static func parseLoginStatusOutput(_ output: String?) -> LoginStatus {
        let normalizedOutput = (output ?? "").lowercased()
        if normalizedOutput.contains("logged in using chatgpt") {
            return .chatGPT
        }
        if normalizedOutput.contains("logged in using access token") {
            return .accessToken
        }
        if normalizedOutput.contains("logged in using an api key")
            || normalizedOutput.contains("logged in using api key") {
            return .apiKey
        }
        if normalizedOutput.contains("not logged in") {
            return .notLoggedIn(output)
        }
        return .unavailable(output)
    }

    private nonisolated static func readFileBackedSubscriptionStatus() -> LoginStatus? {
        guard let auth = readFileBackedAuth() else {
            return nil
        }

        if auth.auth_mode?.lowercased() == "apikey" {
            return .apiKey
        }

        guard let token = auth.tokens?.access_token?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return nil
        }

        if auth.auth_mode?.lowercased() == "agentidentity" {
            return .accessToken
        }

        return .chatGPT
    }

    private nonisolated static func readIDToken() -> String? {
        readFileBackedAuth()?.tokens?.id_token
    }

    private nonisolated static func readFileBackedAuth() -> CodexAuth? {
        guard let data = FileManager.default.contents(atPath: authFileURL.path),
              let auth = try? JSONDecoder().decode(CodexAuth.self, from: data) else {
            return nil
        }
        return auth
    }

    private nonisolated static func readConfigFile() -> String? {
        guard let data = try? Data(contentsOf: configFileURL),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    private nonisolated static func readTomlStringValue(for key: String, in contents: String) -> String? {
        let lines = contents.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            guard let equalsIndex = line.firstIndex(of: "=") else {
                continue
            }

            let parsedKey = line[..<equalsIndex].trimmingCharacters(in: .whitespaces)
            guard parsedKey == key else {
                continue
            }

            let valuePortion = line[line.index(after: equalsIndex)...].trimmingCharacters(in: .whitespaces)
            guard valuePortion.count >= 2,
                  valuePortion.first == "\"",
                  valuePortion.last == "\"" else {
                continue
            }

            return String(valuePortion.dropFirst().dropLast())
        }
        return nil
    }
}
