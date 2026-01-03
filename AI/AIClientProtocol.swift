//
//  AIClientProtocol.swift
//  FileOrganizer
//
//  Protocol defining AI client interface
//

import Foundation

/// Delegate protocol for streaming updates
@MainActor
protocol StreamingDelegate: AnyObject {
    func didReceiveChunk(_ chunk: String)
    func didComplete(content: String)
    func didFail(error: Error)
}

protocol AIClientProtocol: Sendable {
    func analyze(files: [FileItem], customInstructions: String?, personaPrompt: String?, temperature: Double?) async throws -> OrganizationPlan
    var config: AIConfig { get }
    @MainActor var streamingDelegate: StreamingDelegate? { get set }
}



