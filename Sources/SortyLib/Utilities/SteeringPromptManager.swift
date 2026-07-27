//
//  SteeringPromptManager.swift
//  Sorty
//
//  Manages saved steering prompts for AI organization
//

import Foundation
import Combine

public struct SavedSteeringPrompt: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var prompt: String
    public var isPinned: Bool
    public let dateCreated: Date

    public init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        isPinned: Bool = false,
        dateCreated: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.isPinned = isPinned
        self.dateCreated = dateCreated
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case prompt
        case isPinned
        case isDefault
        case dateCreated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        prompt = try container.decode(String.self, forKey: .prompt)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned)
            ?? container.decodeIfPresent(Bool.self, forKey: .isDefault)
            ?? false
        dateCreated = try container.decode(Date.self, forKey: .dateCreated)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(dateCreated, forKey: .dateCreated)
    }
}

@MainActor
public class SteeringPromptManager: ObservableObject {
    @Published public private(set) var prompts: [SavedSteeringPrompt] = []

    private static let storageKey = "sorty.steeringPrompts"

    public static let shared = SteeringPromptManager()

    private init() {
        load()
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addMainActorObserver(forName: .clearAllUsageData, object: nil, queue: .main) { [weak self] in
            self?.clearAll()
        }
    }

    // MARK: - CRUD

    @discardableResult
    public func addPrompt(_ prompt: SavedSteeringPrompt) -> Bool {
        let normalizedName = prompt.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, !hasPrompt(named: normalizedName) else { return false }

        var prompt = prompt
        prompt.name = normalizedName

        prompts.append(prompt)
        save()
        return true
    }

    @discardableResult
    public func updatePrompt(_ prompt: SavedSteeringPrompt) -> Bool {
        let normalizedName = prompt.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalizedName.isEmpty,
            !hasPrompt(named: normalizedName, excluding: prompt.id),
            let index = prompts.firstIndex(where: { $0.id == prompt.id })
        else {
            return false
        }

        var prompt = prompt
        prompt.name = normalizedName

        prompts[index] = prompt
        save()
        return true
    }

    public func hasPrompt(named name: String, excluding promptId: UUID? = nil) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return false }

        return prompts.contains {
            $0.id != promptId
                && $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(normalizedName) == .orderedSame
        }
    }

    public func prompt(id: UUID) -> SavedSteeringPrompt? {
        prompts.first { $0.id == id }
    }

    public func deletePrompt(id: UUID) {
        prompts.removeAll { $0.id == id }
        save()
    }

    public func clearAll() {
        prompts.removeAll()
        UserDefaults.standard.removeObject(forKey: SteeringPromptManager.storageKey)
    }

    public func setPinned(_ isPinned: Bool, id: UUID) {
        guard let index = prompts.firstIndex(where: { $0.id == id }) else { return }
        var updatedPrompts = prompts
        updatedPrompts[index].isPinned = isPinned
        prompts = updatedPrompts
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: SteeringPromptManager.storageKey) else { return }
        do {
            prompts = try JSONDecoder().decode([SavedSteeringPrompt].self, from: data)
            // Remove the temporary stress-test records written by older builds.
            let loadedCount = prompts.count
            prompts.removeAll { prompt in
                prompt.name.hasPrefix("Placeholder Instruction ")
                    && prompt.prompt == "Use placeholder instruction \(prompt.name.dropFirst("Placeholder Instruction ".count)) while testing long saved-instruction lists."
            }
            if prompts.count != loadedCount {
                save()
            }
        } catch {
            print("[SteeringPromptManager] Failed to decode prompts: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(prompts)
            UserDefaults.standard.set(data, forKey: SteeringPromptManager.storageKey)
        } catch {
            print("[SteeringPromptManager] Failed to encode prompts: \(error)")
        }
    }
}
