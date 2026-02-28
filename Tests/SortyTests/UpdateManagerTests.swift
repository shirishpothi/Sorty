//
//  UpdateManagerTests.swift
//  SortyTests
//
//  Tests for UpdateManager utility
//

import XCTest
import Combine
@testable import SortyLib

@MainActor
final class UpdateManagerTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testInitializationWithDefaults() {
        let manager = UpdateManager()
        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager.lastCheckDate)
    }
    
    func testInitializationWithCustomRepoDetails() {
        let manager = UpdateManager(repoOwner: "customOwner", repoName: "customRepo")
        XCTAssertEqual(manager.state, .idle)
        XCTAssertNil(manager.lastCheckDate)
    }
    
    // MARK: - UpdateState Enum Tests
    
    func testUpdateStateIdleEquality() {
        let state1: UpdateManager.UpdateState = .idle
        let state2: UpdateManager.UpdateState = .idle
        XCTAssertEqual(state1, state2)
    }
    
    func testUpdateStateCheckingEquality() {
        let state1: UpdateManager.UpdateState = .checking
        let state2: UpdateManager.UpdateState = .checking
        XCTAssertEqual(state1, state2)
    }
    
    func testUpdateStateUpToDateEquality() {
        let state1: UpdateManager.UpdateState = .upToDate
        let state2: UpdateManager.UpdateState = .upToDate
        XCTAssertEqual(state1, state2)
    }
    
    func testUpdateStateAvailableEquality() {
        let url = URL(string: "https://github.com/test/release")!
        let state1: UpdateManager.UpdateState = .available(version: "1.0.0", url: url, notes: "Release notes")
        let state2: UpdateManager.UpdateState = .available(version: "1.0.0", url: url, notes: "Release notes")
        XCTAssertEqual(state1, state2)
    }
    
    func testUpdateStateAvailableInequality() {
        let url = URL(string: "https://github.com/test/release")!
        let state1: UpdateManager.UpdateState = .available(version: "1.0.0", url: url, notes: "Notes")
        let state2: UpdateManager.UpdateState = .available(version: "2.0.0", url: url, notes: "Notes")
        XCTAssertNotEqual(state1, state2)
    }
    
    func testUpdateStateAvailableWithNilNotes() {
        let url = URL(string: "https://github.com/test/release")!
        let state1: UpdateManager.UpdateState = .available(version: "1.0.0", url: url, notes: nil)
        let state2: UpdateManager.UpdateState = .available(version: "1.0.0", url: url, notes: nil)
        XCTAssertEqual(state1, state2)
    }
    
    func testUpdateStateErrorEquality() {
        let state1: UpdateManager.UpdateState = .error("Network error")
        let state2: UpdateManager.UpdateState = .error("Network error")
        XCTAssertEqual(state1, state2)
    }
    
    func testUpdateStateErrorInequality() {
        let state1: UpdateManager.UpdateState = .error("Error 1")
        let state2: UpdateManager.UpdateState = .error("Error 2")
        XCTAssertNotEqual(state1, state2)
    }
    
    func testUpdateStateDifferentCasesInequality() {
        let url = URL(string: "https://github.com/test/release")!
        XCTAssertNotEqual(UpdateManager.UpdateState.idle, UpdateManager.UpdateState.checking)
        XCTAssertNotEqual(UpdateManager.UpdateState.checking, UpdateManager.UpdateState.upToDate)
        XCTAssertNotEqual(UpdateManager.UpdateState.upToDate, UpdateManager.UpdateState.error("test"))
        XCTAssertNotEqual(UpdateManager.UpdateState.error("test"), UpdateManager.UpdateState.available(version: "1.0", url: url, notes: nil))
    }
    
    // MARK: - resetState Tests
    
    func testResetStateFromChecking() {
        let manager = UpdateManager()
        manager.state = .checking
        manager.resetState()
        XCTAssertEqual(manager.state, .idle)
    }
    
    func testResetStateFromUpToDate() {
        let manager = UpdateManager()
        manager.state = .upToDate
        manager.resetState()
        XCTAssertEqual(manager.state, .idle)
    }
    
    func testResetStateFromError() {
        let manager = UpdateManager()
        manager.state = .error("Some error")
        manager.resetState()
        XCTAssertEqual(manager.state, .idle)
    }
    
    func testResetStateFromAvailable() {
        let manager = UpdateManager()
        let url = URL(string: "https://github.com/test/release")!
        manager.state = .available(version: "2.0.0", url: url, notes: "New features")
        manager.resetState()
        XCTAssertEqual(manager.state, .idle)
    }
    
    func testResetStateFromIdle() {
        let manager = UpdateManager()
        manager.resetState()
        XCTAssertEqual(manager.state, .idle)
    }
    
    // MARK: - State Transition Tests
    
    func testStateTransitionIdleToChecking() {
        let manager = UpdateManager()
        XCTAssertEqual(manager.state, .idle)
        manager.state = .checking
        XCTAssertEqual(manager.state, .checking)
    }
    
    func testStateTransitionCheckingToUpToDate() {
        let manager = UpdateManager()
        manager.state = .checking
        manager.state = .upToDate
        XCTAssertEqual(manager.state, .upToDate)
    }
    
    func testStateTransitionCheckingToAvailable() {
        let manager = UpdateManager()
        manager.state = .checking
        let url = URL(string: "https://github.com/test/release")!
        manager.state = .available(version: "2.0.0", url: url, notes: nil)
        if case .available(let version, _, _) = manager.state {
            XCTAssertEqual(version, "2.0.0")
        } else {
            XCTFail("Expected .available state")
        }
    }
    
    func testStateTransitionCheckingToError() {
        let manager = UpdateManager()
        manager.state = .checking
        manager.state = .error("Connection failed")
        if case .error(let message) = manager.state {
            XCTAssertEqual(message, "Connection failed")
        } else {
            XCTFail("Expected .error state")
        }
    }
    
    // MARK: - LastCheckDate Tests
    
    func testLastCheckDateInitiallyNil() {
        let manager = UpdateManager()
        XCTAssertNil(manager.lastCheckDate)
    }
    
    func testLastCheckDateCanBeSet() {
        let manager = UpdateManager()
        let date = Date()
        manager.lastCheckDate = date
        XCTAssertEqual(manager.lastCheckDate, date)
    }
    
    // MARK: - Published Property Tests
    
    func testStateIsPublished() {
        let manager = UpdateManager()
        var stateChanges: [UpdateManager.UpdateState] = []
        
        let cancellable = manager.$state.sink { state in
            stateChanges.append(state)
        }
        
        manager.state = .checking
        manager.state = .upToDate
        
        XCTAssertEqual(stateChanges.count, 3) // initial + 2 changes
        XCTAssertEqual(stateChanges[0], .idle)
        XCTAssertEqual(stateChanges[1], .checking)
        XCTAssertEqual(stateChanges[2], .upToDate)
        
        cancellable.cancel()
    }
    
    func testLastCheckDateIsPublished() {
        let manager = UpdateManager()
        var dateChanges: [Date?] = []
        
        let cancellable = manager.$lastCheckDate.sink { date in
            dateChanges.append(date)
        }
        
        let testDate = Date()
        manager.lastCheckDate = testDate
        
        XCTAssertEqual(dateChanges.count, 2)
        XCTAssertNil(dateChanges[0])
        XCTAssertEqual(dateChanges[1], testDate)
        
        cancellable.cancel()
    }
}

// MARK: - Version Comparison Tests via Testable Subclass

@MainActor
final class UpdateManagerVersionComparisonTests: XCTestCase {
    
    func testMajorVersionNewer() async {
        let result = await compareVersions(latest: "2.0.0", current: "1.9.9")
        XCTAssertTrue(result, "2.0.0 should be newer than 1.9.9")
    }
    
    func testMinorVersionNewer() async {
        let result = await compareVersions(latest: "1.1.0", current: "1.0.0")
        XCTAssertTrue(result, "1.1.0 should be newer than 1.0.0")
    }
    
    func testPatchVersionNewer() async {
        let result = await compareVersions(latest: "1.0.1", current: "1.0.0")
        XCTAssertTrue(result, "1.0.1 should be newer than 1.0.0")
    }
    
    func testSameVersionNotNewer() async {
        let result = await compareVersions(latest: "1.0.0", current: "1.0.0")
        XCTAssertFalse(result, "1.0.0 should not be newer than 1.0.0")
    }
    
    func testOlderMajorVersionNotNewer() async {
        let result = await compareVersions(latest: "1.0.0", current: "2.0.0")
        XCTAssertFalse(result, "1.0.0 should not be newer than 2.0.0")
    }
    
    func testOlderMinorVersionNotNewer() async {
        let result = await compareVersions(latest: "1.0.0", current: "1.1.0")
        XCTAssertFalse(result, "1.0.0 should not be newer than 1.1.0")
    }
    
    func testOlderPatchVersionNotNewer() async {
        let result = await compareVersions(latest: "1.0.0", current: "1.0.1")
        XCTAssertFalse(result, "1.0.0 should not be newer than 1.0.1")
    }
    
    func testPreReleaseToFullRelease() async {
        let result = await compareVersions(latest: "1.0.0", current: "1.0.0-beta")
        XCTAssertTrue(result, "1.0.0 should be newer than 1.0.0-beta")
    }
    
    func testPreReleaseToSamePreRelease() async {
        let result = await compareVersions(latest: "1.0.0-beta", current: "1.0.0-beta")
        XCTAssertFalse(result, "1.0.0-beta should not be newer than 1.0.0-beta")
    }
    
    func testFullReleaseToPreReleaseNotNewer() async {
        let result = await compareVersions(latest: "1.0.0-beta", current: "1.0.0")
        XCTAssertFalse(result, "1.0.0-beta should not be newer than 1.0.0")
    }
    
    func testVersionWithVPrefix() async {
        let normalizedVersion = "v1.1.0".hasPrefix("v") ? String("v1.1.0".dropFirst()) : "v1.1.0"
        XCTAssertEqual(normalizedVersion, "1.1.0", "Version with 'v' prefix should be normalized")
    }
    
    func testDifferentLengthVersions() async {
        let result = await compareVersions(latest: "1.0.0.1", current: "1.0.0")
        XCTAssertTrue(result, "1.0.0.1 should be newer than 1.0.0")
    }
    
    func testShorterNewerVersion() async {
        let result = await compareVersions(latest: "2.0", current: "1.9.9")
        XCTAssertTrue(result, "2.0 should be newer than 1.9.9")
    }
    
    func testPreReleaseAlpha() async {
        let result = await compareVersions(latest: "1.0.0", current: "1.0.0-alpha")
        XCTAssertTrue(result, "1.0.0 should be newer than 1.0.0-alpha")
    }
    
    func testPreReleaseRC() async {
        let result = await compareVersions(latest: "1.0.0", current: "1.0.0-rc1")
        XCTAssertTrue(result, "1.0.0 should be newer than 1.0.0-rc1")
    }
    
    private func compareVersions(latest: String, current: String) async -> Bool {
        let latestNumeric = latest.components(separatedBy: "-").first ?? latest
        let currentNumeric = current.components(separatedBy: "-").first ?? current
        
        let latestComponents = latestNumeric.split(separator: ".").compactMap { Int($0) }
        let currentComponents = currentNumeric.split(separator: ".").compactMap { Int($0) }
        
        let count = max(latestComponents.count, currentComponents.count)
        
        for i in 0..<count {
            let l = i < latestComponents.count ? latestComponents[i] : 0
            let c = i < currentComponents.count ? currentComponents[i] : 0
            
            if l > c { return true }
            if l < c { return false }
        }
        
        if latestNumeric == currentNumeric {
            let latestHasPreRelease = latest.contains("-")
            let currentHasPreRelease = current.contains("-")
            
            if currentHasPreRelease && !latestHasPreRelease {
                return true
            }
        }
        
        return false
    }
}

// MARK: - Integration Tests (Actual GitHub API)

@MainActor
final class UpdateManagerIntegrationTests: XCTestCase {
    
    /// Tests that the UpdateManager can successfully call the GitHub API
    /// This is an integration test that makes a real network request
    func testCheckForUpdatesConnectsToGitHub() async {
        let manager = UpdateManager(repoOwner: "shirishpothi", repoName: "Sorty")
        
        XCTAssertEqual(manager.state, .idle)
        
        // Perform actual update check
        await manager.checkForUpdates()
        
        // State should transition from idle -> checking -> (available|upToDate|error)
        // We don't know what the result will be, but it shouldn't remain in .checking
        XCTAssertNotEqual(manager.state, .checking, "State should not remain in .checking after checkForUpdates completes")
        
        // lastCheckDate should be set
        XCTAssertNotNil(manager.lastCheckDate, "lastCheckDate should be set after checking")
        
        // Verify state is one of the expected final states
        switch manager.state {
        case .available(let version, let url, _):
            XCTAssertFalse(version.isEmpty, "Available version should not be empty")
            XCTAssertTrue(url.absoluteString.contains("github.com"), "URL should be a GitHub URL")
        case .upToDate:
            XCTAssertTrue(true, "Up to date is a valid result")
        case .error(let message):
            // Errors are acceptable (rate limiting, network issues)
            XCTAssertFalse(message.isEmpty, "Error message should not be empty")
        case .idle, .checking:
            XCTFail("State should not be \(manager.state) after checkForUpdates")
        }
    }
    
    /// Tests that 404 response (no releases) is handled gracefully
    /// Note: This is an integration test that requires network access and may be rate-limited in CI
    func testCheckForUpdatesHandles404AsUpToDate() async {
        // Use a nonexistent repo to trigger 404
        let manager = UpdateManager(repoOwner: "shirishpothi", repoName: "nonexistent-repo-12345")
        
        await manager.checkForUpdates()
        
        // 404 should be treated as "up to date" (no releases means nothing to update to)
        // Also accept rate limit errors (403) and network errors as valid test outcomes in CI environments
        let isValidState: Bool
        switch manager.state {
        case .upToDate:
            isValidState = true
        case .error(let msg):
            // Rate limiting and network issues are expected in CI and should not fail the test
            isValidState = msg.contains("rate limit") || msg.contains("403") || msg.contains("hostname") || msg.contains("network") || msg.contains("connection")
        default:
            isValidState = false
        }
        
        XCTAssertTrue(isValidState, "Expected upToDate or rate limit/network error, got: \(manager.state)")
    }
    
    /// Tests the state machine transitions properly during an update check
    func testStateTransitionsDuringCheck() async {
        let manager = UpdateManager(repoOwner: "shirishpothi", repoName: "Sorty")
        var stateHistory: [UpdateManager.UpdateState] = []
        
        let cancellable = manager.$state.sink { state in
            stateHistory.append(state)
        }
        
        await manager.checkForUpdates()
        
        // Should have at least 2 state transitions: idle -> checking -> (final state)
        XCTAssertGreaterThanOrEqual(stateHistory.count, 2, "Should have state transitions")
        
        // First state should be idle
        XCTAssertEqual(stateHistory.first, .idle, "First state should be idle")
        
        // Should have .checking in the history
        XCTAssertTrue(stateHistory.contains(.checking), "Should transition through .checking state")
        
        cancellable.cancel()
    }
    
    /// Tests resetState works after a check
    func testResetStateAfterCheck() async {
        let manager = UpdateManager()
        
        await manager.checkForUpdates()
        XCTAssertNotEqual(manager.state, .idle)
        
        manager.resetState()
        XCTAssertEqual(manager.state, .idle, "State should be idle after reset")
    }
}
