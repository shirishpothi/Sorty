
import XCTest
@testable import SortyLib

class ExclusionRulesTests: XCTestCase {
    
    var manager: ExclusionRulesManager!
    
    @MainActor
    override func setUp() async throws {
        
        manager = ExclusionRulesManager()
        // Clear existing rules to start fresh
        for rule in manager.rules {
            manager.removeRule(rule)
        }
    }
    
    @MainActor
    func testExtensionExclusion() {
        let rule = ExclusionRule(type: .fileExtension, pattern: "tmp")
        manager.addRule(rule)
        
        let file1 = FileItem(path: "/p/a.tmp", name: "a", extension: "tmp", size: 0, isDirectory: false)
        let file2 = FileItem(path: "/p/b.txt", name: "b", extension: "txt", size: 0, isDirectory: false)
        
        XCTAssertTrue(manager.shouldExclude(file1))
        XCTAssertFalse(manager.shouldExclude(file2))
    }
    
    @MainActor
    func testFileNameExclusion() {
        let rule = ExclusionRule(type: .fileName, pattern: "secret")
        manager.addRule(rule)
        
        let file1 = FileItem(path: "/p/my_secret_file.txt", name: "my_secret_file", extension: "txt", size: 0, isDirectory: false)
        let file2 = FileItem(path: "/p/normal.txt", name: "normal", extension: "txt", size: 0, isDirectory: false)
        
        XCTAssertTrue(manager.shouldExclude(file1))
        XCTAssertFalse(manager.shouldExclude(file2))
    }
    
    @MainActor
    func testFolderNameExclusion() {
        let rule = ExclusionRule(type: .folderName, pattern: "cache")
        manager.addRule(rule)
        
        let file1 = FileItem(path: "/Library/Cache/data.db", name: "data", extension: "db", size: 0, isDirectory: false)
        let file2 = FileItem(path: "/Documents/data.db", name: "data", extension: "db", size: 0, isDirectory: false)
        let file3 = FileItem(path: "/Library/CacheBackup/data.db", name: "data", extension: "db", size: 0, isDirectory: false)

        XCTAssertTrue(manager.shouldExclude(file1))
        XCTAssertFalse(manager.shouldExclude(file2))
        XCTAssertFalse(manager.shouldExclude(file3))
    }
    
    @MainActor
    func testDisabledRule() {
        let rule = ExclusionRule(type: .fileExtension, pattern: "tmp", isEnabled: false)
        manager.addRule(rule)
        
        let file = FileItem(path: "/p/a.tmp", name: "a", extension: "tmp", size: 0, isDirectory: false)
        XCTAssertFalse(manager.shouldExclude(file))
    }

    @MainActor
    func testAddingRuleGeneratesLabelWhenMissing() throws {
        manager.addRule(
            ExclusionRule(
                type: .fileSize,
                description: "   ",
                numericValue: 2_048,
                comparisonGreater: true,
                sizeUnit: .gigabytes
            )
        )

        let rule = try XCTUnwrap(manager.rules.last)
        XCTAssertEqual(rule.description, "Files larger than 2 GB")
    }

    @MainActor
    func testLegacyNaturalLanguagePathMigratesToStructuredRule() throws {
        let suiteName = "ExclusionRulesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["Leave /Users/test/Archive alone"], forKey: "naturalLanguageExceptions")

        let isolatedManager = ExclusionRulesManager(userDefaults: defaults)

        XCTAssertTrue(isolatedManager.naturalLanguageExceptions.isEmpty)
        let rule = try XCTUnwrap(
            isolatedManager.rules.first { $0.pattern == "/Users/test/Archive" }
        )
        XCTAssertEqual(rule.type, .pathContains)
        XCTAssertEqual(rule.isAIGenerated, true)
        XCTAssertNotNil(defaults.data(forKey: "naturalLanguageExceptions"))
    }

    func testFolderNameNaturalLanguageCanMigrateToStructuredRule() throws {
        let exception = NaturalLanguageException(
            text: "Exclude any folder named Archive and everything inside it."
        )

        let rule = try XCTUnwrap(exception.confidentlyStructuredRule)
        XCTAssertEqual(rule.type, .folderName)
        XCTAssertEqual(rule.pattern, "Archive")
        XCTAssertEqual(rule.isAIGenerated, true)
    }

    @MainActor
    func testDisabledNaturalLanguageExceptionIsOmittedFromPrompts() throws {
        let suiteName = "ExclusionRulesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let isolatedManager = ExclusionRulesManager(userDefaults: defaults)
        isolatedManager.addNaturalLanguageException("Leave ~/Documents/Archive alone")

        var exception = try XCTUnwrap(isolatedManager.naturalLanguageExceptions.first)
        exception.isEnabled = false
        isolatedManager.updateNaturalLanguageException(exception)

        XCTAssertTrue(isolatedManager.sanitizedExceptionsForPrompt.isEmpty)
        XCTAssertEqual(exception.referencedPaths, ["~/Documents/Archive"])
    }

    @MainActor
    func testBlankTextPatternsDoNotExcludeEverything() {
        let blankRules = [
            ExclusionRule(type: .fileExtension, pattern: ""),
            ExclusionRule(type: .fileName, pattern: "   "),
            ExclusionRule(type: .folderName, pattern: "\n"),
            ExclusionRule(type: .pathContains, pattern: "\t"),
            ExclusionRule(type: .regex, pattern: "")
        ]

        blankRules.forEach(manager.addRule)

        let file = FileItem(path: "/Users/test/Documents/report.pdf", name: "report", extension: "pdf", size: 0, isDirectory: false)
        XCTAssertFalse(manager.shouldExclude(file))
        XCTAssertTrue(manager.firstMatchingRule(for: file) == nil)
    }

    @MainActor
    func testExtensionExclusionNormalizesDotsAndWhitespace() {
        let rule = ExclusionRule(type: .fileExtension, pattern: " .TMP ")
        manager.addRule(rule)

        let file = FileItem(path: "/p/a.tmp", name: "a", extension: "tmp", size: 0, isDirectory: false)
        XCTAssertTrue(manager.shouldExclude(file))
    }

    func testCompiledMatcherUsesModificationDateWithoutRecompilingPerFile() {
        let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)
        let matcher = ExclusionMatcher(
            rules: [
                ExclusionRule(
                    type: .modificationDate,
                    numericValue: 30,
                    comparisonGreater: true
                )
            ],
            referenceDate: referenceDate
        )
        let file = FileItem(
            path: "/p/archive.txt",
            name: "archive",
            extension: "txt",
            size: 0,
            isDirectory: false,
            creationDate: referenceDate,
            modificationDate: referenceDate.addingTimeInterval(-60 * 24 * 60 * 60)
        )

        XCTAssertTrue(matcher.shouldExclude(file))
    }

    func testCompiledDateMatcherRefreshesOnlyAfterBoundedAge() {
        let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)
        let matcher = ExclusionMatcher(
            rules: [
                ExclusionRule(
                    type: .creationDate,
                    numericValue: 30,
                    comparisonGreater: true
                )
            ],
            referenceDate: referenceDate
        )

        XCTAssertFalse(
            matcher.needsRefresh(at: referenceDate.addingTimeInterval(59))
        )
        XCTAssertTrue(
            matcher.needsRefresh(at: referenceDate.addingTimeInterval(60))
        )

        let refreshedAt = referenceDate.addingTimeInterval(120)
        let refreshed = matcher.refreshed(at: refreshedAt)
        XCTAssertFalse(refreshed.needsRefresh(at: refreshedAt))
    }

    func testCompiledDateMatcherSupportsMinutes() {
        let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)
        let matcher = ExclusionMatcher(
            rules: [
                ExclusionRule(
                    type: .modificationDate,
                    numericValue: 30.0 / 1_440.0,
                    comparisonGreater: true,
                    ageUnit: .minutes,
                    ageIntervalSeconds: 1_800
                )
            ],
            referenceDate: referenceDate
        )
        let oldFile = FileItem(
            path: "/p/old.txt",
            name: "old.txt",
            extension: "txt",
            size: 0,
            isDirectory: false,
            modificationDate: referenceDate.addingTimeInterval(-1_801)
        )

        XCTAssertTrue(matcher.shouldExclude(oldFile))
    }

    func testCompiledMatcherHandlesHundredThousandFilesAcrossConcurrentConsumers() async {
        let matcher = ExclusionMatcher(rules: [
            ExclusionRule(type: .regex, pattern: "^skip_"),
            ExclusionRule(type: .fileExtension, pattern: "tmp"),
        ])
        let fileCount = 100_000
        let workerCount = 4

        let excludedCount = await withTaskGroup(of: Int.self, returning: Int.self) { group in
            for worker in 0..<workerCount {
                group.addTask {
                    var count = 0
                    for index in stride(from: worker, to: fileCount, by: workerCount) {
                        let name = index.isMultiple(of: 2) ? "skip_\(index)" : "keep_\(index)"
                        if matcher.shouldExclude(
                            path: "/large/\(name).txt",
                            name: name,
                            pathExtension: "txt"
                        ) {
                            count += 1
                        }
                    }
                    return count
                }
            }

            var total = 0
            for await count in group {
                total += count
            }
            return total
        }

        XCTAssertEqual(excludedCount, fileCount / 2)
    }

    func testCompiledMatcherPrunesOnlySafePositiveDirectoryRules() {
        let positiveMatcher = ExclusionMatcher(rules: [
            ExclusionRule(type: .folderName, pattern: "node_modules")
        ])
        let negatedMatcher = ExclusionMatcher(rules: [
            ExclusionRule(type: .folderName, pattern: "node_modules", negated: true)
        ])
        let directory = URL(fileURLWithPath: "/project/node_modules/package")

        XCTAssertTrue(positiveMatcher.shouldPruneDirectory(at: directory))
        XCTAssertFalse(negatedMatcher.shouldPruneDirectory(at: directory))
    }

    @MainActor
    func testBlockingRuleReturnsTheExactFolderExclusion() {
        let matchingRule = ExclusionRule(type: .pathContains, pattern: "/Users/test/Downloads")
        manager.addRule(ExclusionRule(type: .folderName, pattern: "Cache"))
        manager.addRule(matchingRule)

        XCTAssertEqual(
            manager.blockingRule(forDirectoryAt: URL(fileURLWithPath: "/Users/test/Downloads"))?.id,
            matchingRule.id
        )
    }

    @MainActor
    func testExclusionEnforcerRemovesNestedViolationsFromAIPlan() {
        let excludedFile = FileItem(path: "/p/cache/secret.tmp", name: "secret", extension: "tmp", size: 0, isDirectory: false)
        let allowedFile = FileItem(path: "/p/report.pdf", name: "report", extension: "pdf", size: 0, isDirectory: false)
        manager.addRule(ExclusionRule(type: .fileExtension, pattern: "tmp"))

        let plan = OrganizationPlan(suggestions: [
            FolderSuggestion(
                folderName: "Documents",
                files: [allowedFile],
                subfolders: [
                    FolderSuggestion(folderName: "Temp", files: [excludedFile])
                ]
            )
        ])

        let result = ExclusionEnforcer(exclusionManager: manager).validate(plan)

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.violationCount, 1)
        XCTAssertEqual(result.violations.first?.file.id, excludedFile.id)
        XCTAssertEqual(result.cleanedPlan?.suggestions.first?.files, [allowedFile])
        XCTAssertTrue(result.cleanedPlan?.suggestions.first?.subfolders.isEmpty == true)
        XCTAssertEqual(result.cleanedPlan?.unorganizedFiles, [excludedFile])
    }

    @MainActor
    func testRemoveLegacyLearningsLinkedRulesKeepsManualRules() {
        let legacyRule = ExclusionRule(
            type: .folderName,
            pattern: "Cache",
            description: ExclusionRulesManager.legacyLearningsLinkedDescription
        )
        let manualRule = ExclusionRule(
            type: .folderName,
            pattern: "Cache",
            description: "User-created cache exclusion"
        )

        manager.addRule(legacyRule)
        manager.addRule(manualRule)

        manager.removeLegacyLearningsLinkedRules()

        XCTAssertFalse(manager.rules.contains(where: { $0.id == legacyRule.id }))
        XCTAssertTrue(manager.rules.contains(where: { $0.id == manualRule.id }))
    }

    @MainActor
    func testRemoveLegacyLearningsLinkedRulesMatchingPatternOnlyRemovesMatchingRule() {
        let matchingLegacyRule = ExclusionRule(
            type: .folderName,
            pattern: "Cache",
            description: ExclusionRulesManager.legacyLearningsLinkedDescription
        )
        let otherLegacyRule = ExclusionRule(
            type: .folderName,
            pattern: "Temp",
            description: ExclusionRulesManager.legacyLearningsLinkedDescription
        )
        let manualRule = ExclusionRule(
            type: .folderName,
            pattern: "Cache",
            description: "Manual cache exclusion"
        )

        manager.addRule(matchingLegacyRule)
        manager.addRule(otherLegacyRule)
        manager.addRule(manualRule)

        manager.removeLegacyLearningsLinkedRules(matchingLearningPattern: "/Users/test/Downloads/Cache")

        XCTAssertFalse(manager.rules.contains(where: { $0.id == matchingLegacyRule.id }))
        XCTAssertTrue(manager.rules.contains(where: { $0.id == otherLegacyRule.id }))
        XCTAssertTrue(manager.rules.contains(where: { $0.id == manualRule.id }))
    }
}
