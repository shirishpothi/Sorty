//
//  CodexSubscriptionClient.swift
//  Sorty
//
//  Uses Codex CLI account sign-in for ChatGPT subscription-backed OpenAI inference.
//

import Foundation

public final class CodexSubscriptionClient: AIClientProtocol, Sendable {
    public let config: AIConfig
    @MainActor public weak var streamingDelegate: StreamingDelegate?

    public init(config: AIConfig) {
        self.config = config
    }

    public func analyze(
        files: [FileItem],
        customInstructions: String? = nil,
        personaPrompt: String? = nil,
        temperature: Double? = nil
    ) async throws -> OrganizationPlan {
        let systemPrompt = config.systemPromptOverride ?? PromptBuilder.buildSystemPrompt(
            personaInfo: personaPrompt ?? "",
            maxTopLevelFolders: config.maxTopLevelFolders,
            mode: config.mode,
            enableTagging: config.enableFileTagging
        )
        let userPrompt = PromptBuilder.buildOrganizationPrompt(
            files: files,
            mode: config.mode,
            namingStyle: config.namingStyle,
            renameNamingOptions: config.renameNamingOptions,
            customNamingInstructions: config.customNamingInstructions,
            renameRules: config.renameRules,
            renameRuleMode: config.renameRuleMode,
            enableReasoning: config.enableReasoning,
            enableSmartRename: config.enableSmartRename,
            includeContentMetadata: true,
            customInstructions: customInstructions
        )
        let prompt = Self.organizationPrompt(systemPrompt: systemPrompt, userPrompt: userPrompt)
        let estimatedPromptTokens = PromptBuilder.estimateTokens(systemPrompt + userPrompt)
        let start = Date()
        let response = try await runCodex(prompt: prompt, imageFiles: [])
        let duration = Date().timeIntervalSince(start)

        var plan = try parseOrganizationResponse(response, files: files)
        plan.generationStats = GenerationStats(
            duration: duration,
            tps: duration > 0 ? Double(response.count / 4) / duration : 0,
            ttft: duration,
            totalTokens: response.count / 4,
            model: config.model,
            filesScanned: files.count,
            totalFileSize: files.reduce(0) { $0 + $1.size },
            promptTokens: estimatedPromptTokens,
            provider: AIProvider.openAI.displayName
        )
        return plan
    }

    public func analyzeWithImages(
        files: [FileItem],
        imageData: [String: Data],
        customInstructions: String? = nil,
        personaPrompt: String? = nil,
        temperature: Double? = nil
    ) async throws -> OrganizationPlan {
        let imageFiles = try Self.writeTemporaryImages(imageData)
        defer {
            for url in imageFiles {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let systemPrompt = config.systemPromptOverride ?? PromptBuilder.buildSystemPrompt(
            personaInfo: personaPrompt ?? "",
            maxTopLevelFolders: config.maxTopLevelFolders,
            mode: config.mode,
            enableTagging: config.enableFileTagging
        )
        let userPrompt = PromptBuilder.buildOrganizationPrompt(
            files: files,
            mode: config.mode,
            namingStyle: config.namingStyle,
            renameNamingOptions: config.renameNamingOptions,
            customNamingInstructions: config.customNamingInstructions,
            renameRules: config.renameRules,
            renameRuleMode: config.renameRuleMode,
            enableReasoning: config.enableReasoning,
            enableSmartRename: config.enableSmartRename,
            includeContentMetadata: true,
            customInstructions: customInstructions,
            analyzedImageFilenames: imageData.keys.sorted()
        )
        let prompt = Self.organizationPrompt(systemPrompt: systemPrompt, userPrompt: userPrompt)
        let estimatedPromptTokens = PromptBuilder.estimateTokens(systemPrompt + userPrompt)
        let start = Date()
        let response = try await runCodex(prompt: prompt, imageFiles: imageFiles)
        let duration = Date().timeIntervalSince(start)

        var plan = try parseOrganizationResponse(response, files: files)
        plan.generationStats = GenerationStats(
            duration: duration,
            tps: duration > 0 ? Double(response.count / 4) / duration : 0,
            ttft: duration,
            totalTokens: response.count / 4,
            model: config.model,
            filesScanned: files.count,
            totalFileSize: files.reduce(0) { $0 + $1.size },
            promptTokens: estimatedPromptTokens,
            provider: AIProvider.openAI.displayName
        )
        return plan
    }

    public func generateText(prompt: String, systemPrompt: String? = nil) async throws -> String {
        let combinedPrompt = [
            systemPrompt,
            prompt
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")

        return try await runCodex(prompt: combinedPrompt, imageFiles: [])
    }

    public func checkHealth() async throws {
        guard ProviderAuthResolver.hasRequiredCredential(for: .openAI, config: config) else {
            throw AIClientError.apiError(
                statusCode: 401,
                message: "Codex CLI sign-in is required. Reauthenticate your ChatGPT subscription in Sorty settings."
            )
        }
        guard Self.resolveCodexExecutablePath() != nil else {
            throw AIClientError.apiError(
                statusCode: 501,
                message: "Codex CLI is required. Install with: npm i -g @openai/codex"
            )
        }
    }

    private func runCodex(prompt: String, imageFiles: [URL]) async throws -> String {
        try await checkHealth()
        guard let codexPath = Self.resolveCodexExecutablePath() else {
            throw AIClientError.apiError(
                statusCode: 501,
                message: "Codex CLI is required. Install with: npm i -g @openai/codex"
            )
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sorty-codex-\(UUID().uuidString).txt")
        let diagnosticsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sorty-codex-diagnostics-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: diagnosticsURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = Self.codexArguments(
            model: config.model,
            outputURL: outputURL,
            imageFiles: imageFiles
        )

        let inputPipe = Pipe()
        FileManager.default.createFile(atPath: diagnosticsURL.path, contents: nil)
        let diagnosticsHandle = try FileHandle(forWritingTo: diagnosticsURL)
        process.standardInput = inputPipe
        process.standardOutput = diagnosticsHandle
        process.standardError = diagnosticsHandle

        do {
            try process.run()
            if let promptData = prompt.data(using: .utf8) {
                try inputPipe.fileHandleForWriting.write(contentsOf: promptData)
            }
            try inputPipe.fileHandleForWriting.close()
            process.waitUntilExit()
        } catch {
            process.terminate()
            try? diagnosticsHandle.close()
            throw AIClientError.networkError(error)
        }
        try? diagnosticsHandle.close()

        let diagnosticData = (try? Data(contentsOf: diagnosticsURL)) ?? Data()
        let diagnostics = String(data: diagnosticData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw AIClientError.apiError(
                statusCode: Int(process.terminationStatus),
                message: diagnostics.isEmpty ? "Codex CLI exited without a response." : diagnostics
            )
        }

        let response = (try? String(contentsOf: outputURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let response, !response.isEmpty else {
            throw AIClientError.invalidResponseFormat
        }
        return response
    }

    private func parseOrganizationResponse(_ response: String, files: [FileItem]) throws -> OrganizationPlan {
        do {
            return try ResponseParser.parseResponse(response, originalFiles: files, mode: config.mode)
        } catch {
            if let partialPlan = ResponseParser.extractPartialResults(response, originalFiles: files, mode: config.mode) {
                return partialPlan
            }
            throw AIClientError.jsonDecodingError(context: error.localizedDescription)
        }
    }

    private nonisolated static func organizationPrompt(systemPrompt: String, userPrompt: String) -> String {
        """
        \(systemPrompt)

        \(userPrompt)

        Return only the JSON object that matches Sorty's requested schema. Do not include Markdown fences, commentary, progress notes, or explanations.
        """
    }

    private nonisolated static func codexArguments(
        model: String,
        outputURL: URL,
        imageFiles: [URL]
    ) -> [String] {
        var arguments = [
            "exec",
            "--ephemeral",
            "--ignore-rules",
            "--skip-git-repo-check",
            "--sandbox",
            "read-only",
            "--output-last-message",
            outputURL.path,
            "--model",
            model
        ]

        for imageFile in imageFiles {
            arguments += ["--image", imageFile.path]
        }

        arguments.append("-")
        return arguments
    }

    private nonisolated static func writeTemporaryImages(_ imageData: [String: Data]) throws -> [URL] {
        try imageData.keys.sorted().map { name in
            let safeName = URL(fileURLWithPath: name).lastPathComponent
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("sorty-codex-\(UUID().uuidString)-\(safeName)")
            guard let data = imageData[name] else { return url }
            try data.write(to: url, options: .atomic)
            return url
        }
    }

    private nonisolated static func resolveCodexExecutablePath() -> String? {
        let paths = [
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.npm-global/bin/codex"
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

            guard process.terminationStatus == 0 else { return nil }
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let resolvedPath = String(data: output, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !resolvedPath.isEmpty,
                FileManager.default.fileExists(atPath: resolvedPath) else {
                return nil
            }
            return resolvedPath
        } catch {
            return nil
        }
    }
}
