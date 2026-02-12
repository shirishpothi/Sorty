//
//  ConflictResolution.swift
//  Sorty
//
//  Smart Conflict Resolution model for file move conflicts
//

import Foundation
import Combine

public enum ConflictAction: String, Codable, Sendable {
    case overwrite
    case keepBoth
    case skip
}

public struct FileConflict: Identifiable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let destinationURL: URL
    public let sourceName: String
    public let destinationName: String
    public let sourceSize: Int64
    public let destinationSize: Int64
    public let sourceDate: Date?
    public let destinationDate: Date?

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        destinationURL: URL,
        sourceName: String,
        destinationName: String,
        sourceSize: Int64,
        destinationSize: Int64,
        sourceDate: Date? = nil,
        destinationDate: Date? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.sourceName = sourceName
        self.destinationName = destinationName
        self.sourceSize = sourceSize
        self.destinationSize = destinationSize
        self.sourceDate = sourceDate
        self.destinationDate = destinationDate
    }
}

@MainActor
public class ConflictResolutionManager: ObservableObject {
    @Published public var pendingConflicts: [FileConflict] = []
    @Published public var resolutions: [UUID: ConflictAction] = [:]
    @Published public var applyToAll: ConflictAction?

    private var continuations: [UUID: AsyncStream<ConflictAction>.Continuation] = [:]

    public init() {}

    public func resolveConflict(_ id: UUID, action: ConflictAction) {
        resolutions[id] = action
        if let continuation = continuations.removeValue(forKey: id) {
            continuation.yield(action)
            continuation.finish()
        }
    }

    public func resolveAll(action: ConflictAction) {
        applyToAll = action
        for conflict in pendingConflicts {
            if resolutions[conflict.id] == nil {
                resolutions[conflict.id] = action
                if let continuation = continuations.removeValue(forKey: conflict.id) {
                    continuation.yield(action)
                    continuation.finish()
                }
            }
        }
    }

    public func waitForResolution(of conflict: FileConflict) async -> ConflictAction {
        if let existing = resolutions[conflict.id] {
            return existing
        }

        if let allAction = applyToAll {
            resolutions[conflict.id] = allAction
            return allAction
        }

        let (stream, continuation) = AsyncStream.makeStream(of: ConflictAction.self)
        continuations[conflict.id] = continuation

        for await action in stream {
            return action
        }

        return .skip
    }

    public func reset() {
        pendingConflicts = []
        resolutions = [:]
        applyToAll = nil
        for (_, continuation) in continuations {
            continuation.finish()
        }
        continuations = [:]
    }
}
