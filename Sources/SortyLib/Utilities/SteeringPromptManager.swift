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
    public var isDefault: Bool
    public let dateCreated: Date

    public init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        isDefault: Bool = false,
        dateCreated: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.isDefault = isDefault
        self.dateCreated = dateCreated
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

        // If new prompt is default, clear default on all others
        if prompt.isDefault {
            for i in prompts.indices {
                prompts[i].isDefault = false
            }
        }
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

        // If this prompt is being set as default, clear others
        if prompt.isDefault {
            for i in prompts.indices {
                prompts[i].isDefault = false
            }
        }
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

    public func deletePrompt(id: UUID) {
        prompts.removeAll { $0.id == id }
        save()
    }

    public func clearAll() {
        prompts.removeAll()
        UserDefaults.standard.removeObject(forKey: SteeringPromptManager.storageKey)
    }

    public func setDefault(id: UUID) {
        for i in prompts.indices {
            prompts[i].isDefault = (prompts[i].id == id)
        }
        save()
    }

    public func clearDefault() {
        for i in prompts.indices {
            prompts[i].isDefault = false
        }
        save()
    }

    /// The currently active default prompt, if any
    public var defaultPrompt: SavedSteeringPrompt? {
        prompts.first(where: { $0.isDefault })
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: SteeringPromptManager.storageKey) else { return }
        do {
            prompts = try JSONDecoder().decode([SavedSteeringPrompt].self, from: data)
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
