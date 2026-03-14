//
//  CodexCLIAuthManager.swift
//  Sorty
//
//  Manages OpenAI authentication via Codex CLI (~/.codex/auth.json)
//

import Foundation
import AppKit

@MainActor
final class CodexCLIAuthManager: ObservableObject {
    static let shared = CodexCLIAuthManager()

    @Published var isAuthenticated = false
    @Published var accountEmail: String?
    @Published var authError: String?
    @Published var isCodexInstalled = false

    enum CredentialStoreMode: String {
        case file
        case keyring
        case auto
        case unknown
    }

    private var authFilePath: String {
        Self.authFileURL.path
    }

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

    init() {
        checkStatus()
    }

    nonisolated var accessToken: String? {
        Self.readAccessToken()
    }

    nonisolated static func readAccessToken() -> String? {
        let path = authFileURL.path
        guard let data = FileManager.default.contents(atPath: path),
              let auth = try? JSONDecoder().decode(CodexAuth.self, from: data) else {
            return nil
        }
        return auth.tokens?.access_token
    }

    nonisolated static func readConfiguredModel() -> String? {
        guard let configContents = readConfigFile() else {
            return nil
        }
        return readTomlStringValue(for: "model", in: configContents)
    }

    nonisolated static func readCredentialStoreMode() -> CredentialStoreMode {
        guard let configContents = readConfigFile(),
              let value = readTomlStringValue(for: "cli_auth_credentials_store", in: configContents) else {
            return .unknown
        }

        switch value.lowercased() {
        case "file":
            return .file
        case "keyring":
            return .keyring
        case "auto":
            return .auto
        default:
            return .unknown
        }
    }

    func checkStatus() {
        isCodexInstalled = checkCodexInstalled()
        let fileExists = FileManager.default.fileExists(atPath: authFilePath)

        guard fileExists,
              let data = FileManager.default.contents(atPath: authFilePath),
              let auth = try? JSONDecoder().decode(CodexAuth.self, from: data),
              let token = auth.tokens?.access_token, !token.isEmpty else {
            isAuthenticated = false
            accountEmail = nil
            if isCodexInstalled {
                switch Self.readCredentialStoreMode() {
                case .keyring:
                    authError = "Codex CLI is configured to store credentials in keychain. Set cli_auth_credentials_store = \"file\" in ~/.codex/config.toml and run codex login again."
                default:
                    authError = nil
                }
            }
            return
        }

        isAuthenticated = true
        accountEmail = extractEmail(from: auth.tokens?.id_token)
        authError = nil
    }

    func signOut() {
        if isCodexInstalled {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["codex", "logout"]
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

    private func prepareLoginScript() throws -> URL {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sorty-codex-login.command")
        let script = """
        #!/bin/zsh
        export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
        codex login
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func checkCodexInstalled() -> Bool {
        let paths = [
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/bin/codex",
        ]

        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }

        // Also check via `which`
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "codex"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func extractEmail(from idToken: String?) -> String? {
        guard let idToken else { return nil }
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var base64 = String(parts[1])
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

            guard line.hasPrefix("\(key)") else {
                continue
            }

            guard let equalsIndex = line.firstIndex(of: "=") else {
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
