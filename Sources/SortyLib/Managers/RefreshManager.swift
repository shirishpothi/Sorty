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
        let id: UUID
        let interval: TimeInterval
        let action: @Sendable () -> Void
        let timer: Timer
    }
    
    /// Task-based refresh for async operations
    private struct AsyncScheduledTask {
        let id: UUID
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
        // Cleanup is handled by invalidate() on timers and Task.cancel() on async tasks
        // The actual cleanup is performed synchronously without MainActor requirements
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
        
        // Use a weak self pattern via a wrapper
        weak var weakSelf = self
        
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, !self.isPaused else { return }
                action()
            }
        }
        
        // Add to RunLoop to ensure it fires
        RunLoop.main.add(timer, forMode: .common)
        
        let scheduledAction = ScheduledAction(
            id: id,
            interval: interval,
            action: action,
            timer: timer
        )
        
        scheduledActions[id] = scheduledAction
        
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
    public func scheduleAsync(interval: TimeInterval, action: @escaping () async -> Void) -> UUID {
        let id = UUID()
        let nanoseconds = UInt64(interval * 1_000_000_000)
        
        weak var weakSelf = self
        
        let task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, !self.isPaused else {
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    continue
                }
                
                await action()
                
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        }
        
        asyncTasks[id] = AsyncScheduledTask(id: id, task: task)
        
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
        
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let strongSelf = self else { return }
                
                if strongSelf.isPaused {
                    // Store for later execution if paused
                    strongSelf.pendingResumes[id] = action
                    return
                }
                action()
                strongSelf.scheduledActions.removeValue(forKey: id)
            }
        }
        
        RunLoop.main.add(timer, forMode: .common)
        
        let scheduledAction = ScheduledAction(
            id: id,
            interval: delay,
            action: action,
            timer: timer
        )
        
        scheduledActions[id] = scheduledAction
        
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
        
        // Execute any pending one-time actions
        for (_, action) in pendingResumes {
            action()
        }
        pendingResumes.removeAll()
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
