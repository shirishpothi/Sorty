import Foundation

enum TestSynchronization {
    // Shared lock for tests that mutate process-wide network privacy mode defaults.
    static let networkPrivacyModeLock = NSLock()
}
