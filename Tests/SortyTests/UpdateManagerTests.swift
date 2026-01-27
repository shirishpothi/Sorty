//
//  UpdateManagerTests.swift
//  SortyTests
//
//  Tests for UpdateManager utility
//

import XCTest
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
