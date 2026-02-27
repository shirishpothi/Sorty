//
//  ApplePrivateCloudComputeClient.swift
//  Sorty
//
//  Apple Private Cloud Compute integration via macOS Shortcuts
//  Uses /usr/bin/shortcuts and auto-discovers a usable Apple
//  Intelligence shortcut without requiring manual setup.
//

import Foundation

public final class ApplePrivateCloudComputeClient: AIClientProtocol, @unchecked Sendable {
    public let config: AIConfig
    @MainActor public weak var streamingDelegate: StreamingDelegate?

    /// Preferred built-in shortcut for Apple Intelligence prompting.
    public static let shortcutName = "Use Model"
    /// Backward-compatible legacy shortcut name used by previous Sorty versions.
    public static let legacyShortcutName = "Sorty-PCC"
    private static let fallbackShortcutNameKeys = ["applePCCShortcutName", "pccShortcutName"]
    private static let cachedResolvedShortcutNameKey = "applePCCResolvedShortcutName"

    public init(config: AIConfig) {
        self.config = config
    }

    // MARK: - AIClientProtocol

    public func analyze(
        files: [FileItem],
        customInstructions: String? = nil,
        personaPrompt: String? = nil,
        temperature: Double? = nil
    ) async throws -> OrganizationPlan {
        let startTime = Date()

        let prompts = PromptBuilder.promptPair(
            for: .standard,
            config: config,
            files: files
        )

        var userPrompt = prompts.user
        if let instructions = customInstructions, !instructions.isEmpty {
            userPrompt = "USER INSTRUCTIONS: \(instructions)\n\n" + userPrompt
        }

        let fullPrompt = "System: \(prompts.system)\n\n\(userPrompt)"

        let content = try await runShortcut(prompt: fullPrompt)

        await streamContent(content)

        var plan = try ResponseParser.parseResponse(content, originalFiles: files, mode: config.mode)
        plan.generationStats = makeStats(from: content, files: files, startTime: startTime)
        return plan
    }

    public func analyzeWithImages(
        files: [FileItem],
        imageData: [String: Data],
        customInstructions: String? = nil,
        personaPrompt: String? = nil,
        temperature: Double? = nil
    ) async throws -> OrganizationPlan {
        if config.enableVision, !imageData.isEmpty {
            DebugLogger.log("ApplePrivateCloudComputeClient: Vision not supported via Shortcuts; falling back to text-only.")
        }
        return try await analyze(
            files: files,
            customInstructions: customInstructions,
            personaPrompt: personaPrompt,
            temperature: temperature
        )
    }

    public func generateText(prompt: String, systemPrompt: String? = nil) async throws -> String {
        let fullPrompt: String
        if let system = systemPrompt {
            fullPrompt = "System: \(system)\n\n\(prompt)"
        } else {
            fullPrompt = prompt
        }
        return try await runShortcut(prompt: fullPrompt)
    }

    public func checkHealth() async throws {
        guard Self.isShortcutInstalled() else {
            throw AIClientError.apiError(
                statusCode: 404,
                message: Self.missingShortcutErrorMessage
            )
        }
    }

    // MARK: - Shortcut Invocation

    /// Run the PCC shortcut with the given prompt and return the model output.
    private func runShortcut(prompt: String) async throws -> String {
        let installedShortcutNames = Self.listShortcutNames()
        let candidates = Self.candidateShortcutNames(
            defaults: UserDefaults.standard,
            installedShortcutNames: installedShortcutNames.isEmpty ? nil : installedShortcutNames
        )

        guard !candidates.isEmpty else {
            throw AIClientError.apiError(
                statusCode: 404,
                message: Self.missingShortcutErrorMessage
            )
        }

        var collectedErrors: [String] = []
        for candidate in candidates {
            do {
                let output = try await runShortcut(named: candidate, prompt: prompt)
                UserDefaults.standard.set(candidate, forKey: Self.cachedResolvedShortcutNameKey)
                return output
            } catch {
                collectedErrors.append(error.localizedDescription)
            }
        }

        throw AIClientError.apiError(
            statusCode: 500,
            message: collectedErrors.first ?? Self.missingShortcutErrorMessage
        )
    }

    private func runShortcut(named shortcutName: String, prompt: String) async throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let outputPath = tempDir.appendingPathComponent("sorty-pcc-output-\(UUID().uuidString).txt")

        defer {
            try? FileManager.default.removeItem(at: outputPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = [
            "run",
            shortcutName,
            "-i", "-",
            "-o", outputPath.path,
            "--output-type", "public.plain-text"
        ]

        let stdinPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                if proc.terminationStatus != 0 {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrText = (String(data: stderrData, encoding: .utf8) ?? "Unknown error")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let actionableError = Self.makeShortcutExecutionError(
                        shortcutName: shortcutName,
                        stderr: stderrText,
                        exitCode: proc.terminationStatus
                    )
                    continuation.resume(throwing: AIClientError.apiError(
                        statusCode: 500,
                        message: actionableError
                    ))
                    return
                }

                do {
                    let output: String
                    if FileManager.default.fileExists(atPath: outputPath.path) {
                        output = try String(contentsOf: outputPath, encoding: .utf8)
                    } else {
                        output = ""
                    }
                    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        continuation.resume(throwing: AIClientError.apiError(
                            statusCode: 502,
                            message: "Shortcut \"\(shortcutName)\" returned empty output. Ensure the last Shortcut action returns text from the model response."
                        ))
                    } else {
                        continuation.resume(returning: trimmed)
                    }
                } catch {
                    continuation.resume(throwing: AIClientError.apiError(
                        statusCode: 500,
                        message: "Failed to read Shortcut output for \"\(shortcutName)\": \(error.localizedDescription)"
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: AIClientError.networkError(error))
                return
            }

            if let promptData = prompt.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(promptData)
            }
            try? stdinPipe.fileHandleForWriting.close()
        }
    }

    // MARK: - Availability

    /// Check whether the required Shortcut is installed.
    static func isShortcutInstalled() -> Bool {
        resolveShortcutName() != nil
    }

    private static func resolveShortcutName() -> String? {
        let installedShortcutNames = listShortcutNames()
        return resolveShortcutName(
            installedShortcutNames: installedShortcutNames,
            defaults: UserDefaults.standard
        )
    }

    static func resolveShortcutName(
        installedShortcutNames: Set<String>,
        defaults: UserDefaults
    ) -> String? {
        guard !installedShortcutNames.isEmpty else {
            defaults.removeObject(forKey: cachedResolvedShortcutNameKey)
            return nil
        }

        if let cachedShortcutName = defaults.string(forKey: cachedResolvedShortcutNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !cachedShortcutName.isEmpty,
           shortcutNameExists(cachedShortcutName, in: installedShortcutNames) {
            let matchedName = canonicalShortcutName(for: cachedShortcutName, in: installedShortcutNames) ?? cachedShortcutName
            defaults.set(matchedName, forKey: cachedResolvedShortcutNameKey)
            return matchedName
        }

        for key in fallbackShortcutNameKeys {
            if let customName = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !customName.isEmpty,
               shortcutNameExists(customName, in: installedShortcutNames) {
                let matchedName = canonicalShortcutName(for: customName, in: installedShortcutNames) ?? customName
                defaults.set(matchedName, forKey: cachedResolvedShortcutNameKey)
                return matchedName
            }
        }

        for builtInName in [shortcutName, legacyShortcutName] {
            if shortcutNameExists(builtInName, in: installedShortcutNames) {
                let matchedName = canonicalShortcutName(for: builtInName, in: installedShortcutNames) ?? builtInName
                defaults.set(matchedName, forKey: cachedResolvedShortcutNameKey)
                return matchedName
            }
        }

        defaults.removeObject(forKey: cachedResolvedShortcutNameKey)
        return nil
    }

    private static func candidateShortcutNames(
        defaults: UserDefaults,
        installedShortcutNames: Set<String>?
    ) -> [String] {
        var candidates: [String] = []

        func appendUnique(_ name: String?) {
            guard let raw = name?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }

            if let installedShortcutNames {
                guard let canonical = canonicalShortcutName(for: raw, in: installedShortcutNames) else { return }
                if !candidates.contains(where: { $0.caseInsensitiveCompare(canonical) == .orderedSame }) {
                    candidates.append(canonical)
                }
                return
            }

            if !candidates.contains(where: { $0.caseInsensitiveCompare(raw) == .orderedSame }) {
                candidates.append(raw)
            }
        }

        appendUnique(defaults.string(forKey: cachedResolvedShortcutNameKey))

        for key in fallbackShortcutNameKeys {
            appendUnique(defaults.string(forKey: key))
        }

        appendUnique(shortcutName)
        appendUnique(legacyShortcutName)

        return candidates
    }

    private static func listShortcutNames() -> Set<String> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return []
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return Set(
                output
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        } catch {
            return []
        }
    }

    // MARK: - Helpers

    private static var missingShortcutErrorMessage: String {
        "No usable Apple Intelligence Shortcut found. Sorty auto-detects \"\(legacyShortcutName)\" and \"\(shortcutName)\". Open the Shortcuts app and ensure at least one exists, or set a custom name with `defaults write com.sorty.app applePCCShortcutName -string \"<Shortcut Name>\"`."
    }

    private static func shortcutNameExists(_ candidate: String, in installedNames: Set<String>) -> Bool {
        canonicalShortcutName(for: candidate, in: installedNames) != nil
    }

    private static func canonicalShortcutName(for candidate: String, in installedNames: Set<String>) -> String? {
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return installedNames.first {
            $0.compare(trimmedCandidate, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    private static func makeShortcutExecutionError(shortcutName: String, stderr: String, exitCode: Int32) -> String {
        if stderr.localizedCaseInsensitiveContains("not found") || stderr.localizedCaseInsensitiveContains("does not exist") {
            return "Shortcut \"\(shortcutName)\" was not found at runtime. Sorty auto-detects \"\(legacyShortcutName)\" and \"\(Self.shortcutName)\"."
        }

        if stderr.localizedCaseInsensitiveContains("permission") || stderr.localizedCaseInsensitiveContains("not authorized") {
            return "Shortcut \"\(shortcutName)\" requires automation permission. Open System Settings → Privacy & Security → Automation, then allow Sorty to control Shortcuts."
        }

        if stderr.localizedCaseInsensitiveContains("input of the shortcut could not be processed") {
            return "Shortcut \"\(shortcutName)\" rejected text input. Use an Apple Intelligence shortcut that accepts text input and returns text output."
        }

        if stderr.isEmpty {
            return "Shortcut \"\(shortcutName)\" failed with exit code \(exitCode)."
        }

        return "Shortcut \"\(shortcutName)\" failed with exit code \(exitCode): \(stderr)"
    }

    private func makeStats(
        from content: String,
        files: [FileItem],
        startTime: Date
    ) -> GenerationStats {
        let duration = Date().timeIntervalSince(startTime)
        let estimatedTokens = content.count / 4
        let tps = duration > 0 ? Double(estimatedTokens) / duration : 0

        return GenerationStats(
            duration: duration,
            tps: tps,
            ttft: 0,
            totalTokens: estimatedTokens,
            model: "Apple Private Cloud Compute",
            filesScanned: files.count,
            totalFileSize: files.reduce(0) { $0 + $1.size },
            promptTokens: nil
        )
    }

    private func streamContent(_ content: String) async {
        let chunkSize = 20
        var currentIndex = content.startIndex

        while currentIndex < content.endIndex {
            let nextIndex = content.index(currentIndex, offsetBy: chunkSize, limitedBy: content.endIndex) ?? content.endIndex
            let chunk = String(content[currentIndex..<nextIndex])

            await MainActor.run {
                streamingDelegate?.didReceiveChunk(chunk)
            }

            try? await Task.sleep(nanoseconds: 5_000_000)
            currentIndex = nextIndex
        }

        await MainActor.run {
            streamingDelegate?.didComplete(content: content)
        }
    }
}
