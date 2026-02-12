//
//  FolderScheduler.swift
//  Sorty
//
//  Manages scheduled "Spring Cleaning" organization runs for watched folders
//

import Foundation
import Combine

public extension Notification.Name {
    static let scheduledOrganizationTriggered = Notification.Name("scheduledOrganizationTriggered")
}

public enum ScheduleFrequency: String, Codable, Sendable, CaseIterable {
    case daily
    case weekly
    case biweekly
    case monthly

    public var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .biweekly: return "Every 2 Weeks"
        case .monthly: return "Monthly"
        }
    }
}

public struct ScheduleEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var folderId: UUID
    public var folderPath: String
    public var frequency: ScheduleFrequency
    public var dayOfWeek: Int?
    public var hour: Int
    public var minute: Int
    public var isEnabled: Bool
    public var lastRun: Date?
    public var nextRun: Date?

    public init(
        id: UUID = UUID(),
        folderId: UUID,
        folderPath: String,
        frequency: ScheduleFrequency,
        dayOfWeek: Int? = nil,
        hour: Int = 9,
        minute: Int = 0,
        isEnabled: Bool = true,
        lastRun: Date? = nil,
        nextRun: Date? = nil
    ) {
        self.id = id
        self.folderId = folderId
        self.folderPath = folderPath
        self.frequency = frequency
        self.dayOfWeek = dayOfWeek
        self.hour = hour
        self.minute = minute
        self.isEnabled = isEnabled
        self.lastRun = lastRun
        self.nextRun = nextRun
    }
}

@MainActor
public class FolderScheduler: ObservableObject {
    @Published public var schedules: [ScheduleEntry] = []

    private let userDefaults = UserDefaults.standard
    private let storageKey = "folderSchedules"
    private nonisolated(unsafe) var timerCancellable: AnyCancellable?

    public init() {
        loadSchedules()
        startTimer()
    }

    deinit {
        timerCancellable?.cancel()
    }

    // MARK: - Public API

    public func addSchedule(for folder: WatchedFolder, frequency: ScheduleFrequency, dayOfWeek: Int?, hour: Int, minute: Int) {
        var entry = ScheduleEntry(
            folderId: folder.id,
            folderPath: folder.path,
            frequency: frequency,
            dayOfWeek: dayOfWeek,
            hour: hour,
            minute: minute
        )
        entry.nextRun = calculateNextRun(for: entry)
        schedules.append(entry)
        saveSchedules()
    }

    public func removeSchedule(id: UUID) {
        schedules.removeAll { $0.id == id }
        saveSchedules()
    }

    public func toggleSchedule(id: UUID) {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        schedules[index].isEnabled.toggle()
        if schedules[index].isEnabled {
            schedules[index].nextRun = calculateNextRun(for: schedules[index])
        }
        saveSchedules()
    }

    public func updateSchedule(_ entry: ScheduleEntry) {
        guard let index = schedules.firstIndex(where: { $0.id == entry.id }) else { return }
        schedules[index] = entry
        schedules[index].nextRun = calculateNextRun(for: schedules[index])
        saveSchedules()
    }

    public func schedule(for folderId: UUID) -> ScheduleEntry? {
        schedules.first { $0.folderId == folderId }
    }

    public func calculateNextRun(for schedule: ScheduleEntry) -> Date {
        let calendar = Calendar.current
        let now = Date()

        var components = DateComponents()
        components.hour = schedule.hour
        components.minute = schedule.minute
        components.second = 0

        switch schedule.frequency {
        case .daily:
            var candidate = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) ?? now
            if candidate <= now {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
            }
            return candidate

        case .weekly:
            components.weekday = schedule.dayOfWeek ?? 1
            var candidate = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) ?? now
            if candidate <= now {
                candidate = calendar.date(byAdding: .weekOfYear, value: 1, to: candidate) ?? candidate
            }
            return candidate

        case .biweekly:
            components.weekday = schedule.dayOfWeek ?? 1
            var candidate = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) ?? now
            if candidate <= now {
                candidate = calendar.date(byAdding: .weekOfYear, value: 2, to: candidate) ?? candidate
            }
            return candidate

        case .monthly:
            components.day = schedule.dayOfWeek ?? 1
            var candidate = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) ?? now
            if candidate <= now {
                candidate = calendar.date(byAdding: .month, value: 1, to: candidate) ?? candidate
            }
            return candidate
        }
    }

    // MARK: - Private

    private func startTimer() {
        timerCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.checkSchedules()
                }
            }
    }

    private func checkSchedules() {
        let now = Date()
        var hasChanges = false

        for index in schedules.indices {
            guard schedules[index].isEnabled,
                  let nextRun = schedules[index].nextRun,
                  nextRun <= now else { continue }

            let entry = schedules[index]
            DebugLogger.log("Scheduled organization triggered for: \(entry.folderPath)")

            NotificationCenter.default.post(
                name: .scheduledOrganizationTriggered,
                object: nil,
                userInfo: [
                    "folderId": entry.folderId.uuidString,
                    "folderPath": entry.folderPath
                ]
            )

            schedules[index].lastRun = now
            schedules[index].nextRun = calculateNextRun(for: schedules[index])
            hasChanges = true
        }

        if hasChanges {
            saveSchedules()
        }
    }

    private func loadSchedules() {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ScheduleEntry].self, from: data) else { return }
        schedules = decoded
    }

    private func saveSchedules() {
        if let encoded = try? JSONEncoder().encode(schedules) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }
}
