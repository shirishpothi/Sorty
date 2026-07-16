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
        guard Self.resolveCodexExecutablePath() != nil else {
            throw AIClientError.apiError(
                statusCode: 501,
                message: "Codex CLI is required. Install with: npm i -g @openai/codex"
            )
        }

        switch CodexCLIAuthManager.readLoginStatus() {
        case .chatGPT, .accessToken:
            return
        case .apiKey:
            throw AIClientError.apiError(
                statusCode: 401,
                message: "Codex CLI is signed in with an API key. Use ChatGPT sign-in or a Codex access token for subscription-backed inference."
            )
        case .notLoggedIn:
            throw AIClientError.apiError(
                statusCode: 401,
                message: "Codex CLI sign-in is required. Reauthenticate your ChatGPT subscription in Sorty settings."
            )
        case .unavailable(let message):
            throw AIClientError.apiError(
                statusCode: 401,
                message: message ?? "Codex CLI sign-in could not be verified. Run `codex login status` in Terminal."
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
        let schemaURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sorty-codex-schema-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: diagnosticsURL)
            try? FileManager.default.removeItem(at: schemaURL)
        }
        try Self.writeOrganizationResponseSchema(to: schemaURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = Self.codexArguments(
            model: config.model,
            outputURL: outputURL,
            schemaURL: schemaURL,
            imageFiles: imageFiles
        )

        let inputPipe = Pipe()
        FileManager.default.createFile(atPath: diagnosticsURL.path, contents: nil)
        let diagnosticsHandle = try FileHandle(forWritingTo: diagnosticsURL)
        let diagnosticsLock = NSLock()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let stdoutStreamer = CodexOutputStreamer { [weak self] chunk in
            guard let self else { return }
            Task { @MainActor in
                self.streamingDelegate?.didReceiveChunk(chunk)
            }
        }
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            diagnosticsLock.lock()
            try? diagnosticsHandle.write(contentsOf: data)
            diagnosticsLock.unlock()
            stdoutStreamer.process(data)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            diagnosticsLock.lock()
            try? diagnosticsHandle.write(contentsOf: data)
            diagnosticsLock.unlock()
        }

        do {
            try process.run()
            if let promptData = prompt.data(using: .utf8) {
                try inputPipe.fileHandleForWriting.write(contentsOf: promptData)
            }
            try inputPipe.fileHandleForWriting.close()
            process.waitUntilExit()
        } catch {
            process.terminate()
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            try? diagnosticsHandle.close()
            throw AIClientError.networkError(error)
        }
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        stdoutStreamer.finish()
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
        await MainActor.run {
            streamingDelegate?.didComplete(content: response)
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
        schemaURL: URL,
        imageFiles: [URL]
    ) -> [String] {
        var arguments = [
            "exec",
            "--ephemeral",
            "--ignore-user-config",
            "--ignore-rules",
            "--skip-git-repo-check",
            "--sandbox",
            "read-only",
            "--json",
            "--output-last-message",
            outputURL.path,
            "--output-schema",
            schemaURL.path,
            "--model",
            model
        ]

        for imageFile in imageFiles {
            arguments += ["--image", imageFile.path]
        }

        arguments.append("-")
        return arguments
    }

    private nonisolated static func writeOrganizationResponseSchema(to url: URL) throws {
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "folders": [
                    "type": "array",
                    "items": folderSchema()
                ],
                "folder_assignments": [
                    "type": ["array", "null"],
                    "items": folderSchema()
                ],
                "unorganized": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "filename": ["type": "string"],
                            "reason": ["type": "string"]
                        ],
                        "required": ["filename", "reason"]
                    ]
                ],
                "unorganized_ids": [
                    "type": ["array", "null"],
                    "items": ["type": "integer"]
                ],
                "notes": ["type": "string"]
            ],
            "required": ["folders", "folder_assignments", "unorganized", "unorganized_ids", "notes"],
            "$defs": [
                "folder": folderSchema()
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private nonisolated static func folderSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "name": ["type": "string"],
                "description": ["type": ["string", "null"]],
                "reasoning": ["type": ["string", "null"]],
                "subfolders": [
                    "type": ["array", "null"],
                    "items": ["$ref": "#/$defs/folder"]
                ],
                "files": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "filename": ["type": "string"],
                            "suggested_name": ["type": ["string", "null"]],
                            "rename_reason": ["type": ["string", "null"]],
                            "rename_confidence": ["type": ["number", "null"]],
                            "tags": [
                                "type": ["array", "null"],
                                "items": ["type": "string"]
                            ],
                            "comment": ["type": ["string", "null"]]
                        ],
                        "required": [
                            "filename",
                            "suggested_name",
                            "rename_reason",
                            "rename_confidence",
                            "tags",
                            "comment"
                        ]
                    ]
                ],
                "tags": [
                    "type": ["array", "null"],
                    "items": ["type": "string"]
                ],
                "comment": ["type": ["string", "null"]],
                "semantic_tags": [
                    "type": ["array", "null"],
                    "items": ["type": "string"]
                ],
                "confidence": ["type": ["number", "null"]],
                "rule_id": ["type": ["string", "null"]],
                "file_ids": [
                    "type": ["array", "null"],
                    "items": ["type": "integer"]
                ],
                "rename_suggestions": [
                    "type": ["array", "null"],
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "file_id": ["type": "integer"],
                            "suggested_name": ["type": ["string", "null"]],
                            "rename_reason": ["type": ["string", "null"]],
                            "rename_confidence": ["type": ["number", "null"]]
                        ],
                        "required": [
                            "file_id",
                            "suggested_name",
                            "rename_reason",
                            "rename_confidence"
                        ]
                    ]
                ]
            ],
            "required": [
                "name",
                "description",
                "reasoning",
                "subfolders",
                "files",
                "tags",
                "comment",
                "semantic_tags",
                "confidence",
                "rule_id",
                "file_ids",
                "rename_suggestions"
            ]
        ]
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
            "/Applications/Codex.app/Contents/Resources/codex",
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

private final class CodexOutputStreamer: @unchecked Sendable {
    private let lock = NSLock()
    private var lineBuffer = ""
    private let onChunk: @Sendable (String) -> Void

    init(onChunk: @escaping @Sendable (String) -> Void) {
        self.onChunk = onChunk
    }

    func process(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }

        lock.lock()
        lineBuffer += text
        let lines = lineBuffer.split(separator: "\n", omittingEmptySubsequences: false)
        let completeLines = lineBuffer.hasSuffix("\n") ? lines : Array(lines.dropLast())
        lineBuffer = lineBuffer.hasSuffix("\n") ? "" : String(lines.last ?? "")
        lock.unlock()

        for line in completeLines {
            processLine(String(line))
        }
    }

    func finish() {
        lock.lock()
        let pending = lineBuffer
        lineBuffer = ""
        lock.unlock()

        if !pending.isEmpty {
            processLine(pending)
        }
    }

    private func processLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let chunk = Self.extractVisibleChunk(from: json) {
            onChunk(chunk)
        }
    }

    private static func extractVisibleChunk(from json: [String: Any]) -> String? {
        if let type = json["type"] as? String {
            switch type {
            case "agent_message_delta", "response.output_text.delta", "message_delta",
                 "agent_reasoning_delta", "response.reasoning.delta", "reasoning_delta":
                return nonEmptyString(json["delta"] ?? json["content"] ?? json["text"] ?? json["summary"])
            case "agent_message", "assistant_message", "message":
                return nonEmptyString(json["message"] ?? json["content"] ?? json["text"])
            case "item.completed", "item.updated":
                if let item = json["item"] as? [String: Any] {
                    return extractVisibleChunk(from: item)
                }
            default:
                break
            }
        }

        if let item = json["item"] as? [String: Any],
           let chunk = extractVisibleChunk(from: item) {
            return chunk
        }

        if let message = json["message"] as? [String: Any] {
            return extractMessageContent(from: message)
        }

        if let content = json["content"] as? [[String: Any]] {
            return content.compactMap(extractMessageContent(from:)).joinedNonEmpty()
        }

        return nil
    }

    private static func extractMessageContent(from json: [String: Any]) -> String? {
        if let text = nonEmptyString(json["text"] ?? json["content"] ?? json["delta"]) {
            return text
        }

        if let content = json["content"] as? [[String: Any]] {
            return content.compactMap(extractMessageContent(from:)).joinedNonEmpty()
        }

        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }
}

private extension Array where Element == String {
    func joinedNonEmpty() -> String? {
        let value = joined()
        return value.isEmpty ? nil : value
    }
}
