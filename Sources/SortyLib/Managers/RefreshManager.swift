//
//  RefreshManager.swift
//  Sorty
//
//  Consolidated timer management to prevent retain cycles and reduce memory overhead
//

import Foundation
import Combine

/// A consolidated timer manager that handles multiple refresh timers with different intervals
/// Uses weak self patterns to prevent retain cycles and provides centralized control
@MainActor
public final class RefreshManager: ObservableObject {
    
    // MARK: - Types
    
    /// Represents a scheduled refresh action
    private struct ScheduledAction: @unchecked Sendable {
        let timer: Timer
    }
    
    /// Task-based refresh for async operations
    private struct AsyncScheduledTask {
        let task: Task<Void, Never>
    }
    
    // MARK: - Properties
    
    private var scheduledActions: [UUID: ScheduledAction] = [:]
    private var asyncTasks: [UUID: AsyncScheduledTask] = [:]
    private var isPaused: Bool = false
    private var pendingResumes: [UUID: () -> Void] = [:]
    
    /// Shared instance for app-wide use (optional singleton pattern)
    public static let shared = RefreshManager()
    
    // MARK: - Initialization
    
    public init() {}
    
    deinit {
        for action in scheduledActions.values {
            action.timer.invalidate()
        }
        for task in asyncTasks.values {
            task.task.cancel()
        }
    }
    
    // MARK: - Timer Scheduling
    
    /// Schedule a repeating timer with the specified interval and action
    /// - Parameters:
    ///   - interval: Time interval between firings
    ///   - action: The action to perform (captured with weak self)
    /// - Returns: A unique identifier for the scheduled timer
    @discardableResult
    public func schedule(interval: TimeInterval, action: @escaping @Sendable () -> Void) -> UUID {
        let id = UUID()
        let safeInterval = normalizedRepeatingInterval(interval)

        let timer = Timer(timeInterval: safeInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isPaused else { return }
                action()
            }
        }
        RunLoop.main.add(timer, forMode: .common)

        scheduledActions[id] = ScheduledAction(timer: timer)
        
        // Fire immediately if not paused
        if !isPaused {
            action()
        }
        
        return id
    }
    
    /// Schedule an async task that repeats with the specified interval
    /// Uses Swift Concurrency instead of Timer for better cancellation support
    /// - Parameters:
    ///   - interval: Time interval between executions (in seconds)
    ///   - action: Async action to perform (captured with weak self)
    /// - Returns: A unique identifier for the scheduled task
    @discardableResult
    public func scheduleAsync(
        interval: TimeInterval,
        action: @escaping @Sendable () async -> Void
    ) -> UUID {
        let id = UUID()
        let safeInterval = normalizedRepeatingInterval(interval)
        
        let task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                if self?.isPaused == false {
                    await action()
                }

                do {
                    try await Task.sleep(for: .seconds(safeInterval))
                } catch {
                    return
                }
            }
        }
        
        asyncTasks[id] = AsyncScheduledTask(task: task)
        
        return id
    }
    
    /// Schedule a one-time delayed action
    /// - Parameters:
    ///   - delay: Time to wait before executing
    ///   - action: Action to perform after delay
    /// - Returns: A unique identifier for the scheduled action
    @discardableResult
    public func scheduleOnce(delay: TimeInterval, action: @escaping @Sendable () -> Void) -> UUID {
        let id = UUID()
        let safeDelay = delay.isFinite ? max(0, delay) : 0

        let timer = Timer(timeInterval: safeDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                
                if self.isPaused {
                    // Store for later execution if paused
                    self.pendingResumes[id] = action
                    return
                }
                action()
                self.scheduledActions.removeValue(forKey: id)
            }
        }
        RunLoop.main.add(timer, forMode: .common)

        scheduledActions[id] = ScheduledAction(timer: timer)
        
        return id
    }
    
    // MARK: - Control Methods
    
    /// Cancel a specific scheduled timer by its ID
    public func cancel(_ id: UUID) {
        if let action = scheduledActions.removeValue(forKey: id) {
            action.timer.invalidate()
        }
        
        if let task = asyncTasks.removeValue(forKey: id) {
            task.task.cancel()
        }
        
        pendingResumes.removeValue(forKey: id)
    }
    
    /// Cancel all scheduled timers and tasks
    public func cancelAll() {
        // Cancel all timer-based actions
        for action in scheduledActions.values {
            action.timer.invalidate()
        }
        scheduledActions.removeAll()
        
        // Cancel all async tasks
        for task in asyncTasks.values {
            task.task.cancel()
        }
        asyncTasks.removeAll()
        
        // Clear pending resumes
        pendingResumes.removeAll()
    }
    
    /// Pause all timers (they won't fire until resumed)
    public func pause() {
        isPaused = true
    }
    
    /// Resume all paused timers
    public func resume() {
        isPaused = false

        // Clear bookkeeping before invoking callbacks because a callback may
        // synchronously schedule or cancel more work on this manager.
        let pending = pendingResumes
        pendingResumes.removeAll()
        for (id, action) in pending {
            scheduledActions.removeValue(forKey: id)?.timer.invalidate()
            action()
        }
    }
    
    /// Check if the manager is currently paused
    public var isCurrentlyPaused: Bool {
        isPaused
    }
    
    /// Get the count of active timers
    public var activeTimerCount: Int {
        scheduledActions.count + asyncTasks.count
    }
    
    // MARK: - Convenience Methods
    
    /// Schedule multiple actions with different intervals at once
    public func scheduleBatch(_ schedules: [(interval: TimeInterval, action: @Sendable () -> Void)]) -> [UUID] {
        var ids: [UUID] = []
        for schedule in schedules {
            let id = self.schedule(interval: schedule.interval, action: schedule.action)
            ids.append(id)
        }
        return ids
    }
    
    /// Create a coordinated refresh group that can be controlled together
    public func createCoordinatedGroup() -> CoordinatedRefreshGroup {
        CoordinatedRefreshGroup(manager: self)
    }

    private func normalizedRepeatingInterval(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite, interval > 0 else { return 1 }
        return max(interval, 0.01)
    }
}

// MARK: - Coordinated Refresh Group

/// A group of related refresh timers that can be controlled together
@MainActor
public final class CoordinatedRefreshGroup {
    private weak var manager: RefreshManager?
    private var timerIDs: [UUID] = []
    
    fileprivate init(manager: RefreshManager) {
        self.manager = manager
    }
    
    /// Add a timer to this coordinated group
    @discardableResult
    public func addTimer(interval: TimeInterval, action: @escaping @Sendable () -> Void) -> UUID {
        guard let manager = manager else { return UUID() }
        let id = manager.schedule(interval: interval, action: action)
        timerIDs.append(id)
        return id
    }
    
    /// Cancel all timers in this group
    public func cancelAll() {
        guard let manager = manager else { return }
        for id in timerIDs {
            manager.cancel(id)
        }
        timerIDs.removeAll()
    }
    
    /// Pause all timers in this group
    public func pause() {
        guard let manager = manager else { return }
        manager.pause()
    }
    
    /// Resume all timers in this group
    public func resume() {
        guard let manager = manager else { return }
        manager.resume()
    }
}
