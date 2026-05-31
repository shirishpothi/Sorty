//
//  NotificationManagerTests.swift
//  SortyTests
//
//  Unit tests for the new notification system
//

import XCTest
@testable import SortyLib

// MARK: - NotificationSettings Tests

@MainActor
final class NotificationSettingsTests: XCTestCase {
    
    func testDefaultSettings() {
        let settings = NotificationSettings.default
        
        XCTAssertTrue(settings.inAppHUD, "In-app HUD should be enabled by default")
        XCTAssertTrue(settings.systemNotifications, "System notifications should be enabled by default")
        XCTAssertTrue(settings.showActionButtons, "Action buttons should be enabled by default")
        XCTAssertTrue(settings.showPreviewReadyInForeground, "Preview-ready notifications should work in foreground by default")
        XCTAssertTrue(settings.batchSummary, "Batch summary notifications should be enabled by default")
        XCTAssertTrue(settings.alwaysShowCriticalErrors, "Critical errors should always notify by default")
        XCTAssertTrue(settings.systemNotificationSounds, "System notification sounds should be enabled by default")
    }

    
    func testSettingsEncoding() throws {
        var settings = NotificationSettings()
        settings.inAppHUD = true
        settings.systemNotifications = false
        settings.hudSounds = false
        settings.systemNotificationSounds = true
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)
        XCTAssertNotNil(data, "Settings should be encodable")
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(NotificationSettings.self, from: data)
        XCTAssertEqual(decoded, settings, "Decoded settings should match original")
    }
    
    
    func testNotificationBackendDisplayNames() {
        XCTAssertFalse(NotificationBackend.native.displayName.isEmpty)
    }
    
    func testNotificationBackendDescriptions() {
        XCTAssertFalse(NotificationBackend.native.description.isEmpty)
    }
}

// MARK: - BatchSummaryStats Tests

final class BatchSummaryStatsTests: XCTestCase {
    
    func testTotalOperations() {
        let stats = BatchSummaryStats(
            filesMoved: 10,
            foldersCreated: 3,
            filesRenamed: 5,
            filesTagged: 2
        )
        
        XCTAssertEqual(stats.totalOperations, 17, "Total should be filesMoved + filesRenamed + filesTagged")
    }
    
    func testHasErrors() {
        let noErrors = BatchSummaryStats(errorsEncountered: 0)
        XCTAssertFalse(noErrors.hasErrors)
        
        let withErrors = BatchSummaryStats(errorsEncountered: 5)
        XCTAssertTrue(withErrors.hasErrors)
    }
    
    func testIsSuccessful() {
        let successful = BatchSummaryStats(filesMoved: 1)
        XCTAssertTrue(successful.isSuccessful)
        
        let successfulWithFolders = BatchSummaryStats(foldersCreated: 1)
        XCTAssertTrue(successfulWithFolders.isSuccessful)
        
        let noOps = BatchSummaryStats()
        XCTAssertFalse(noOps.isSuccessful)
    }
    
    func testDefaultInit() {
        let stats = BatchSummaryStats()
        
        XCTAssertEqual(stats.filesMoved, 0)
        XCTAssertEqual(stats.foldersCreated, 0)
        XCTAssertEqual(stats.filesRenamed, 0)
        XCTAssertEqual(stats.filesTagged, 0)
        XCTAssertEqual(stats.duplicatesFound, 0)
        XCTAssertEqual(stats.errorsEncountered, 0)
        XCTAssertEqual(stats.duration, 0)
        XCTAssertEqual(stats.folderName, "")
        XCTAssertNil(stats.folderPath)
        XCTAssertFalse(stats.canUndo)
    }
}

// MARK: - NotificationType Tests

final class NotificationTypeTests: XCTestCase {
    
    func testProcessingCompleteType() {
        let type = NotificationType.processingComplete(
            fileCount: 10,
            folderName: "Documents",
            folderPath: "/Users/test/Documents",
            canUndo: true
        )
        
        XCTAssertFalse(type.isCritical)
    }
    
    func testProcessingErrorCritical() {
        let critical = NotificationType.processingError(
            message: "Critical failure",
            isCritical: true,
            canRetry: false
        )
        XCTAssertTrue(critical.isCritical)
        
        let nonCritical = NotificationType.processingError(
            message: "Minor issue",
            isCritical: false,
            canRetry: true
        )
        XCTAssertFalse(nonCritical.isCritical)
    }
    
    func testInfoType() {
        let info = NotificationType.info(title: "Test", message: "Message")
        XCTAssertFalse(info.isCritical)
    }
    
    func testLegacyInitializers() {
        // Test legacy processingComplete initializer
        let complete = NotificationType.processingComplete(fileCount: 5, folderName: "Test")
        XCTAssertFalse(complete.isCritical)
        
        // Test legacy processingError initializer
        let error = NotificationType.processingError(message: "Error")
        XCTAssertFalse(error.isCritical)
        
        // Test legacy batchSummary initializer
        let summary = NotificationType.batchSummary(processed: 10, errors: 2, duration: 5.0)
        XCTAssertFalse(summary.isCritical)
    }
}

// MARK: - HUDNotification Tests

final class HUDNotificationTests: XCTestCase {
    
    func testHUDNotificationEquality() {
        let notification1 = HUDNotification(
            title: "Test",
            message: "Message",
            icon: "checkmark",
            iconColor: .green,
            timestamp: Date(),
            playSound: true
        )
        
        // Same notification should equal itself
        XCTAssertEqual(notification1, notification1)
        
        // Different notifications should not be equal (different IDs)
        let notification2 = HUDNotification(
            title: "Test",
            message: "Message",
            icon: "checkmark",
            iconColor: .green,
            timestamp: Date(),
            playSound: true
        )
        XCTAssertNotEqual(notification1, notification2)
    }
    
    func testHUDNotificationProperties() {
        let date = Date()
        let notification = HUDNotification(
            title: "Test Title",
            message: "Test Message",
            icon: "star.fill",
            iconColor: .yellow,
            timestamp: date,
            playSound: false
        )
        
        XCTAssertEqual(notification.title, "Test Title")
        XCTAssertEqual(notification.message, "Test Message")
        XCTAssertEqual(notification.icon, "star.fill")
        XCTAssertEqual(notification.timestamp, date)
        XCTAssertFalse(notification.playSound)
    }
}

// MARK: - NotificationSettingsManager Tests

final class NotificationSettingsManagerTests: XCTestCase {
    
    @MainActor
    func testSharedInstance() {
        let manager = NotificationSettingsManager.shared
        XCTAssertNotNil(manager)
    }
    
    @MainActor
    func testReset() {
        let manager = NotificationSettingsManager.shared
        
        // Modify settings
        manager.settings.inAppHUD = false
        manager.settings.systemNotifications = false
        
        // Reset
        manager.reset()
        
        // Verify defaults restored
        XCTAssertTrue(manager.settings.inAppHUD)
        XCTAssertTrue(manager.settings.systemNotifications)
    }
}

// MARK: - NotificationManager Tests

@MainActor
final class NotificationManagerTests: XCTestCase {
    
    func testSharedInstance() {
        let manager = NotificationManager.shared
        XCTAssertNotNil(manager)
    }
    
    func testInitialState() {
        let manager = NotificationManager.shared
        XCTAssertNil(manager.currentHUDNotification)
        XCTAssertTrue(manager.hudNotificationQueue.isEmpty)
    }
    
    func testDismissHUD() {
        let manager = NotificationManager.shared
        
        // Dismiss should work even with no notification
        manager.dismissHUD()
        XCTAssertNil(manager.currentHUDNotification)
    }
}

// MARK: - NotificationAction Tests

final class NotificationActionTests: XCTestCase {
    
    func testNotificationActions() {
        // Verify all action cases exist
        let apply = NotificationAction.apply
        let undo = NotificationAction.undo
        let openFolder = NotificationAction.openFolder(path: "/test")
        let showDetails = NotificationAction.showDetails
        let retry = NotificationAction.retry
        let redo = NotificationAction.redoWithModel
        let dismiss = NotificationAction.dismiss
        
        // Basic check that actions are distinct
        if case .apply = apply {
            XCTAssertTrue(true)
        } else {
            XCTFail("apply action should match .apply")
        }

        if case .undo = undo {
            XCTAssertTrue(true)
        } else {
            XCTFail("undo action should match .undo")
        }
        
        if case .openFolder(let path) = openFolder {
            XCTAssertEqual(path, "/test")
        } else {
            XCTFail("openFolder action should match .openFolder")
        }
        
        if case .showDetails = showDetails {
            XCTAssertTrue(true)
        } else {
            XCTFail("showDetails action should match .showDetails")
        }
        
        if case .retry = retry {
            XCTAssertTrue(true)
        } else {
            XCTFail("retry action should match .retry")
        }

        if case .redoWithModel = redo {
            XCTAssertTrue(true)
        } else {
            XCTFail("redo action should match .redoWithModel")
        }
        
        if case .dismiss = dismiss {
            XCTAssertTrue(true)
        } else {
            XCTFail("dismiss action should match .dismiss")
        }
    }
}

// MARK: - Additional NotificationSettings Tests

final class ExtendedNotificationSettingsTests: XCTestCase {
    
    
    func testNotificationTypesFlags() {
        var settings = NotificationSettings()
        
        // All should be true by default
        XCTAssertTrue(settings.processingComplete)
        XCTAssertTrue(settings.processingErrors)
        XCTAssertTrue(settings.batchSummary)
        XCTAssertTrue(settings.alwaysShowCriticalErrors)
        
        // Test toggling
        settings.processingComplete = false
        settings.processingErrors = false
        settings.batchSummary = false
        settings.alwaysShowCriticalErrors = false
        
        XCTAssertFalse(settings.processingComplete)
        XCTAssertFalse(settings.processingErrors)
        XCTAssertFalse(settings.batchSummary)
        XCTAssertFalse(settings.alwaysShowCriticalErrors)
    }
    
    func testSoundSettings() {
        var settings = NotificationSettings()
        
        XCTAssertTrue(settings.systemNotificationSounds)
        XCTAssertFalse(settings.hudSounds)
        
        settings.systemNotificationSounds = false
        settings.hudSounds = true
        
        XCTAssertFalse(settings.systemNotificationSounds)
        XCTAssertTrue(settings.hudSounds)
    }
}

// MARK: - NotificationManager Notification Names Tests

final class NotificationManagerNamesTests: XCTestCase {
    
    func testOrganizationNotificationNamesExist() {
        XCTAssertNotNil(NSNotification.Name.undoLastOrganization)
        XCTAssertNotNil(NSNotification.Name.requestUndoOrganizationConfirmation)
        XCTAssertNotNil(NSNotification.Name.retryLastOrganization)
        XCTAssertNotNil(NSNotification.Name.requestRetryOrganizationConfirmation)
        XCTAssertNotNil(NSNotification.Name.showOrganizationDetails)
        XCTAssertNotNil(NSNotification.Name.showOrganizationPreview)
        XCTAssertNotNil(NSNotification.Name.requestApplyOrganizationConfirmation)
        XCTAssertNotNil(NSNotification.Name.openOrganizedFolder)
        XCTAssertNotNil(NSNotification.Name.redoOrganizationWithModel)
        XCTAssertNotNil(NSNotification.Name.requestRedoOrganizationWithModelConfirmation)
    }
    
    func testOrganizationNotificationNamesAreUnique() {
        let names: [NSNotification.Name] = [
            .undoLastOrganization,
            .requestUndoOrganizationConfirmation,
            .retryLastOrganization,
            .requestRetryOrganizationConfirmation,
            .showOrganizationDetails,
            .showOrganizationPreview,
            .requestApplyOrganizationConfirmation,
            .openOrganizedFolder,
            .redoOrganizationWithModel,
            .requestRedoOrganizationWithModelConfirmation
        ]
        
        let uniqueNames = Set(names.map { $0.rawValue })
        XCTAssertEqual(names.count, uniqueNames.count, "All notification names should be unique")
    }
}

// MARK: - Extended NotificationManager Tests

@MainActor
final class NotificationManagerExtendedTests: XCTestCase {
    
    func testHUDNotificationQueueManagement() {
        let manager = NotificationManager.shared
        
        XCTAssertTrue(manager.hudNotificationQueue.isEmpty, "Queue should start empty")
        
        manager.dismissHUD()
        XCTAssertNil(manager.currentHUDNotification, "Should be nil after dismiss")
    }
    
    func testNotificationPermissionStatusInitialValue() {
        let manager = NotificationManager.shared
        XCTAssertNotNil(manager.notificationPermissionStatus)
    }
    
}

// MARK: - Extended BatchSummaryStats Tests

final class BatchSummaryStatsExtendedTests: XCTestCase {
    
    func testFullBatchSummary() {
        let stats = BatchSummaryStats(
            filesMoved: 50,
            foldersCreated: 10,
            filesRenamed: 15,
            filesTagged: 5,
            duplicatesFound: 3,
            errorsEncountered: 2,
            duration: 125.5,
            folderName: "Documents",
            folderPath: "/Users/test/Documents",
            canUndo: true
        )
        
        XCTAssertEqual(stats.filesMoved, 50)
        XCTAssertEqual(stats.foldersCreated, 10)
        XCTAssertEqual(stats.filesRenamed, 15)
        XCTAssertEqual(stats.filesTagged, 5)
        XCTAssertEqual(stats.duplicatesFound, 3)
        XCTAssertEqual(stats.errorsEncountered, 2)
        XCTAssertEqual(stats.duration, 125.5)
        XCTAssertEqual(stats.folderName, "Documents")
        XCTAssertEqual(stats.folderPath, "/Users/test/Documents")
        XCTAssertTrue(stats.canUndo)
        
        XCTAssertEqual(stats.totalOperations, 70) // 50 + 15 + 5
        XCTAssertTrue(stats.hasErrors)
        XCTAssertTrue(stats.isSuccessful)
    }
    
    func testBatchSummaryWithZeroErrors() {
        let stats = BatchSummaryStats(
            filesMoved: 10,
            errorsEncountered: 0
        )
        
        XCTAssertFalse(stats.hasErrors)
    }
    
    func testBatchSummarySuccessWithOnlyFolders() {
        let stats = BatchSummaryStats(
            foldersCreated: 5
        )
        
        XCTAssertTrue(stats.isSuccessful)
        XCTAssertEqual(stats.totalOperations, 0)
    }
}

// MARK: - Extended NotificationType Tests

final class NotificationTypeExtendedTests: XCTestCase {
    
    func testProcessingCompleteWithAllParams() {
        let type = NotificationType.processingComplete(
            fileCount: 42,
            folderName: "MyFolder",
            folderPath: "/Users/test/MyFolder",
            canUndo: true
        )
        
        if case .processingComplete(let count, let name, let path, let undo, _) = type {
            XCTAssertEqual(count, 42)
            XCTAssertEqual(name, "MyFolder")
            XCTAssertEqual(path, "/Users/test/MyFolder")
            XCTAssertTrue(undo)
        } else {
            XCTFail("Should be processingComplete")
        }
    }
    
    func testBatchSummaryWithStats() {
        let stats = BatchSummaryStats(
            filesMoved: 100,
            foldersCreated: 20,
            errorsEncountered: 5,
            duration: 60.0,
            folderName: "Organized",
            folderPath: "/path/to/organized",
            canUndo: true
        )
        
        let type = NotificationType.batchSummary(stats: stats)
        
        if case .batchSummary(let s, _) = type {
            XCTAssertEqual(s.filesMoved, 100)
            XCTAssertEqual(s.foldersCreated, 20)
            XCTAssertEqual(s.errorsEncountered, 5)
            XCTAssertEqual(s.duration, 60.0)
            XCTAssertEqual(s.folderName, "Organized")
            XCTAssertEqual(s.folderPath, "/path/to/organized")
            XCTAssertTrue(s.canUndo)
        } else {
            XCTFail("Should be batchSummary")
        }
    }
    
    func testProcessingErrorWithRetry() {
        let type = NotificationType.processingError(
            message: "Network timeout",
            isCritical: false,
            canRetry: true
        )
        
        if case .processingError(let msg, let folderPath, let critical, let retry, _) = type {
            XCTAssertEqual(msg, "Network timeout")
            XCTAssertNil(folderPath)
            XCTAssertFalse(critical)
            XCTAssertTrue(retry)
        } else {
            XCTFail("Should be processingError")
        }
    }
    
    func testInfoNotificationType() {
        let type = NotificationType.info(title: "Info Title", message: "Info Message")
        
        if case .info(let title, let message) = type {
            XCTAssertEqual(title, "Info Title")
            XCTAssertEqual(message, "Info Message")
        } else {
            XCTFail("Should be info type")
        }
        
        XCTAssertFalse(type.isCritical)
    }
}

// MARK: - NotificationSettings Extended Tests

final class NotificationSettingsExtendedTests: XCTestCase {
    
    func testAllNotificationSettingsProperties() {
        var settings = NotificationSettings()
        
        settings.inAppHUD = false
        settings.systemNotifications = false
        settings.showActionButtons = false
        settings.processingComplete = false
        settings.processingErrors = false
        settings.batchSummary = false
        settings.alwaysShowCriticalErrors = false
        settings.systemNotificationSounds = false
        settings.hudSounds = true
        
        XCTAssertFalse(settings.inAppHUD)
        XCTAssertFalse(settings.systemNotifications)
        XCTAssertFalse(settings.showActionButtons)
        XCTAssertFalse(settings.processingComplete)
        XCTAssertFalse(settings.processingErrors)
        XCTAssertFalse(settings.batchSummary)
        XCTAssertFalse(settings.alwaysShowCriticalErrors)
        XCTAssertFalse(settings.systemNotificationSounds)
        XCTAssertTrue(settings.hudSounds)
    }
    
}

// MARK: - Notification Action Curation Tests

@MainActor
final class NotificationActionCurationTests: XCTestCase {

    func testPreviewReadyActionsPrioritizeReviewThenApply() {
        let labels = NotificationManager.shared.notificationActionLabels(
            for: .previewReady(folderName: "Inbox", folderPath: "/tmp/Inbox")
        )

        XCTAssertEqual(labels, ["Review Plan", "Apply Now", "Try Another Model"])
    }

    func testProcessingCompleteActionsStayShortAndUseful() {
        let labels = NotificationManager.shared.notificationActionLabels(
            for: .processingComplete(
                fileCount: 24,
                folderName: "Downloads",
                folderPath: "/tmp/Downloads",
                canUndo: true
            )
        )

        XCTAssertEqual(labels, ["Open Folder", "Show Details", "Undo", "Try Another Model"])
    }

    func testConfigurationErrorsSkipRetryAndRedo() {
        let labels = NotificationManager.shared.notificationActionLabels(
            for: .processingError(
                message: "No AI provider configured",
                folderPath: "/tmp/Downloads",
                isCritical: false,
                canRetry: true
            )
        )

        XCTAssertEqual(labels, ["Show Details", "Open Folder"])
    }

    func testTimeoutErrorsPrioritizeRecovery() {
        let labels = NotificationManager.shared.notificationActionLabels(
            for: .processingError(
                message: "Request timed out after 60 seconds",
                folderPath: "/tmp/Downloads",
                isCritical: false,
                canRetry: true
            )
        )

        XCTAssertEqual(labels, ["Show Details", "Retry", "Open Folder", "Try Another Model"])
    }
}
