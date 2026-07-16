import XCTest
@testable import SortyLib

final class EntitlementSystemTests: XCTestCase {
    @MainActor
    func testDormantLicensingRolloutLeavesEveryCapabilityAvailable() throws {
        let manager = EntitlementManager(
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!,
            secureStore: EntitlementSecureStore(
                rootDirectory: try makeTemporaryDirectory(),
                secretStore: InMemoryEntitlementSecretStore()
            )
        )

        XCTAssertFalse(LicensingRollout.isEnabled)
        XCTAssertEqual(manager.state, .bundleUnlocked)
        XCTAssertEqual(manager.snapshot.enabledCapabilities, Set(ProductCapability.allCases))
        XCTAssertEqual(manager.snapshot.unlockedEntitlements, Set(ProductEntitlement.allCases))
        XCTAssertFalse(manager.snapshot.isFreeTier)
    }

    func testProductionGumroadConfigurationIsPinnedToSortyProduct() {
        let configuration = LicenseServiceConfiguration.current()

        XCTAssertEqual(configuration.productID, "w0WiZtzKwIjM7_xdOTSi2g==")
        XCTAssertEqual(configuration.purchaseURL.absoluteString, "https://shirishpothi.gumroad.com/l/Sorty")
        XCTAssertEqual(configuration.verificationURL.absoluteString, "https://api.gumroad.com/v2/licenses/verify")
        XCTAssertTrue(configuration.isConfigured)
    }

    @MainActor
    func testPreviewEntitlementOverridesAreDebugOnly() async throws {
        let suiteName = "EntitlementSystemTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("bundle_unlocked", forKey: "entitlementPreviewState")
        let manager = EntitlementManager(
            userDefaults: defaults,
            configuration: makeConfiguration(),
            secureStore: EntitlementSecureStore(
                rootDirectory: try makeTemporaryDirectory(),
                secretStore: InMemoryEntitlementSecretStore()
            ),
            licensingEnabled: true
        )

        await manager.bootstrapIfNeeded()

        #if DEBUG
        XCTAssertEqual(manager.state, .bundleUnlocked)
        #else
        XCTAssertEqual(manager.state, .free)
        #endif
    }

    func testFreeSnapshotRestrictsPaidCapabilitiesAndProviders() {
        let snapshot = EntitlementCatalog.shared.snapshot(for: .free)

        XCTAssertTrue(snapshot.isEnabled(.organization))
        XCTAssertTrue(snapshot.isEnabled(.basicHistory))
        XCTAssertFalse(snapshot.isEnabled(.deepScan))
        XCTAssertFalse(snapshot.isEnabled(.duplicateDetection))
        XCTAssertEqual(snapshot.maxWatchedFolders, 1)
        XCTAssertEqual(snapshot.maxStorageLocations, 1)
        XCTAssertEqual(snapshot.maxLocalOrganizations, 5)
        XCTAssertTrue(snapshot.isProviderSelectable(.openAI))
        XCTAssertFalse(snapshot.isProviderSelectable(.githubCopilot))
        XCTAssertEqual(snapshot.supportedAuthMethods(for: .openAI), [.apiKey])
    }

    func testSanitizedConfigRemovesLockedBehaviorAndAuth() {
        var config = AIConfig(
            provider: .openAI,
            apiURL: AIProvider.openAI.defaultAPIURL,
            apiKey: nil,
            model: AIProvider.openAI.defaultModel,
            temperature: 0.9,
            requiresAPIKey: true,
            enableDeepScan: true,
            detectDuplicates: true,
            enableFileTagging: true,
            showStatsForNerds: true,
            storeDuplicateMetadata: true,
            automationProvider: .anthropic,
            automationModel: AIProvider.anthropic.defaultModel
        )
        config.setAuthMethod(.accountSignIn, for: .openAI)

        let sanitized = EntitlementCatalog.shared.snapshot(for: .free).sanitized(config)

        XCTAssertEqual(sanitized.authMethod(for: .openAI), .apiKey)
        XCTAssertEqual(sanitized.temperature, EntitlementSnapshot.defaultLockedTemperature)
        XCTAssertFalse(sanitized.enableDeepScan)
        XCTAssertFalse(sanitized.detectDuplicates)
        XCTAssertFalse(sanitized.enableFileTagging)
        XCTAssertFalse(sanitized.showStatsForNerds)
        XCTAssertFalse(sanitized.storeDuplicateMetadata)
        XCTAssertNil(sanitized.automationProvider)
        XCTAssertNil(sanitized.automationModel)
    }

    func testAIClientFactoryRejectsBlockedPremiumProvider() {
        let config = AIConfig(
            provider: .githubCopilot,
            apiURL: AIProvider.githubCopilot.defaultAPIURL,
            apiKey: nil,
            model: AIProvider.githubCopilot.defaultModel,
            requiresAPIKey: true
        )

        XCTAssertThrowsError(
            try AIClientFactory.createClient(
                config: config,
                entitlements: EntitlementCatalog.shared.snapshot(for: .free)
            )
        ) { error in
            guard case AIClientError.apiError(let statusCode, let message) = error else {
                return XCTFail("Expected an entitlement error, got: \(error)")
            }
            XCTAssertEqual(statusCode, 403)
            XCTAssertTrue(message.contains("paid provider pack"))
        }
    }

    @MainActor
    func testStorageLocationsManagerEnforcesFreeLimit() async throws {
        let suiteName = "EntitlementSystemTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = StorageLocationsManager(
            userDefaults: defaults,
            entitlementSnapshotProvider: { EntitlementCatalog.shared.snapshot(for: .free) }
        )
        let firstURL = try makeTemporaryDirectory()
        let secondURL = try makeTemporaryDirectory()

        try manager.addLocation(url: firstURL)

        XCTAssertThrowsError(try manager.addLocation(url: secondURL))
        XCTAssertEqual(manager.enabledLocations.count, 1)
        let promptContext = await manager.generatePromptContext()
        XCTAssertNotNil(promptContext)
        XCTAssertEqual(
            manager.limitMessage,
            StorageLocationAccessError.limitReached(maxAllowed: 1).localizedDescription
        )
    }

    @MainActor
    func testLearningsManagerSkipsPromptInjectionAndWritesWhenLocked() async {
        let suiteName = "EntitlementSystemTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        EntitlementRuntime.update(EntitlementCatalog.shared.snapshot(for: .free))
        let manager = LearningsManager(userDefaults: defaults)
        await manager.grantConsent()

        manager.recordGuidingInstruction("Keep invoices by year", for: "/tmp/Invoices", fileCount: 8)
        manager.recordCorrection(originalPath: "/tmp/Invoices/a.pdf", newPath: "/tmp/Invoices/2026/a.pdf")
        manager.setLearningsModelOverride(provider: AIProvider.openAI, model: "gpt-5-mini")

        XCTAssertEqual(manager.generatePromptContext(forFolder: "/tmp/Invoices"), "")
        XCTAssertEqual(manager.generateModelDirectoryContext(), "")
        XCTAssertTrue(manager.currentProfile?.guidingInstructionsHistory.isEmpty ?? true)
        XCTAssertTrue(manager.currentProfile?.corrections.isEmpty ?? true)
    }

    func testSecureStoreEncryptsVerifiedPayloadAndLicenseKey() throws {
        let payload = makePayload(
            nextValidationAt: Date().addingTimeInterval(3_600),
            graceExpiresAt: Date().addingTimeInterval(86_400)
        )
        let rootDirectory = try makeTemporaryDirectory()
        let secureStore = EntitlementSecureStore(
            rootDirectory: rootDirectory,
            secretStore: InMemoryEntitlementSecretStore()
        )

        XCTAssertTrue(secureStore.saveLicenseKeys(["alpha-key"]))
        try secureStore.saveCachedPayload(payload)

        let encryptedContents = String(
            decoding: try Data(contentsOf: rootDirectory.appendingPathComponent("license-cache.enc")),
            as: UTF8.self
        )
        XCTAssertFalse(encryptedContents.contains("deep_scan"))
        XCTAssertEqual(secureStore.storedLicenseKeys(), ["alpha-key"])
        let restoredPayload = try secureStore.loadCachedPayload()
        XCTAssertEqual(restoredPayload?.status, payload.status)
        XCTAssertEqual(restoredPayload?.entitlementSet, payload.entitlementSet)
        XCTAssertEqual(restoredPayload?.activeLicenses, payload.activeLicenses)
    }

    @MainActor
    func testExpiredCachedPayloadUsesGraceOnlyWhenStatusIsActive() async throws {
        let now = Date()

        let activeManager = try makeCachedManager(status: .active, now: now)
        await activeManager.bootstrapIfNeeded()
        guard case .grace = activeManager.state else {
            return XCTFail("Expected grace state, got \(activeManager.state)")
        }

        let revokedManager = try makeCachedManager(status: .revoked, now: now)
        await revokedManager.bootstrapIfNeeded()
        guard case .expired(let entitlements) = revokedManager.state else {
            return XCTFail("Expected expired state, got \(revokedManager.state)")
        }
        XCTAssertEqual(entitlements, [.deepScan])
    }

    func testGumroadClientVerifiesPinnedProductAndBuildsProEntitlement() async throws {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [GumroadStubURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        let response = """
        {
          "success": true,
          "uses": 1,
          "purchase": {
            "product_id": "w0WiZtzKwIjM7_xdOTSi2g==",
            "product_name": "Sorty",
            "email": "buyer@example.com",
            "sale_id": "sale-1",
            "sale_timestamp": "2026-07-16T00:00:00Z",
            "refunded": false,
            "disputed": false,
            "chargebacked": false
          }
        }
        """
        GumroadStubURLProtocol.stub = .init(statusCode: 200, data: Data(response.utf8))
        defer { GumroadStubURLProtocol.stub = nil }

        let client = GumroadLicenseServiceClient(
            configuration: makeConfiguration(),
            session: session,
            now: { Date(timeIntervalSince1970: 10_000) }
        )
        let payload = try await client.requestEntitlements(
            licenseKeys: ["ABCD-1234-EFGH-5678"],
            reason: .activate
        )

        XCTAssertTrue(payload.bundleUnlocked)
        XCTAssertEqual(payload.entitlementSet, Set(ProductEntitlement.allCases))
        XCTAssertEqual(payload.customerEmail, "buyer@example.com")
        XCTAssertEqual(payload.activeLicenses.first?.saleID, "sale-1")
        XCTAssertEqual(payload.activeLicenses.first?.keyHint, "ABCD...5678")

        let request = try XCTUnwrap(GumroadStubURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.gumroad.test/v2/licenses/verify")
        let body = String(decoding: try XCTUnwrap(GumroadStubURLProtocol.lastRequestBody), as: UTF8.self)
        XCTAssertTrue(body.contains("product_id=w0WiZtzKwIjM7_xdOTSi2g%3D%3D"))
        XCTAssertTrue(body.contains("increment_uses_count=false"))
    }

    func testGumroadClientHonorsInternetPrivacyMode() async {
        let suiteName = "EntitlementSystemTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: NetworkPrivacyPolicy.internetPrivacyModeKey)
        NetworkPrivacyPolicy.setTestDefaultsSuiteName(suiteName)
        defer {
            NetworkPrivacyPolicy.setTestDefaultsSuiteName(nil)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let client = GumroadLicenseServiceClient(configuration: makeConfiguration())
        do {
            _ = try await client.requestEntitlements(
                licenseKeys: ["license"],
                reason: .refresh
            )
            XCTFail("Expected privacy mode rejection")
        } catch let error as LicenseServiceError {
            XCTAssertEqual(error, .invalidConfiguration(NetworkPrivacyPolicy.blockedMessage))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeConfiguration() -> LicenseServiceConfiguration {
        LicenseServiceConfiguration(
            productID: LicenseServiceConfiguration.sortyProductID,
            purchaseURL: LicenseServiceConfiguration.sortyPurchaseURL,
            verificationURL: URL(string: "https://api.gumroad.test/v2/licenses/verify")!,
            validationInterval: 3_600,
            gracePeriod: 86_400
        )
    }

    @MainActor
    private func makeCachedManager(
        status: LicenseValidationStatus,
        now: Date
    ) throws -> EntitlementManager {
        let store = EntitlementSecureStore(
            rootDirectory: try makeTemporaryDirectory(),
            secretStore: InMemoryEntitlementSecretStore()
        )
        let originalPayload = makePayload(
            nextValidationAt: now.addingTimeInterval(-60),
            graceExpiresAt: now.addingTimeInterval(7_200)
        )
        let payload = LicenseEntitlementPayload(
            status: status,
            issuedAt: originalPayload.issuedAt,
            validatedAt: originalPayload.validatedAt,
            nextValidationAt: originalPayload.nextValidationAt,
            graceExpiresAt: originalPayload.graceExpiresAt,
            bundleUnlocked: originalPayload.bundleUnlocked,
            entitlements: originalPayload.entitlements,
            customerEmail: originalPayload.customerEmail,
            warningMessage: originalPayload.warningMessage,
            activeLicenses: originalPayload.activeLicenses
        )
        _ = store.saveLicenseKeys(["cached-license"])
        try store.saveCachedPayload(payload)

        return EntitlementManager(
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!,
            configuration: makeConfiguration(),
            secureStore: store,
            serviceClient: MockLicenseServiceClient { _, _ in
                throw LicenseServiceError.serviceUnavailable
            },
            licensingEnabled: true,
            now: { now }
        )
    }

    private func makePayload(
        nextValidationAt: Date,
        graceExpiresAt: Date
    ) -> LicenseEntitlementPayload {
        return LicenseEntitlementPayload(
            status: .active,
            issuedAt: Date(timeIntervalSince1970: 1_000),
            validatedAt: Date(timeIntervalSince1970: 2_000),
            nextValidationAt: nextValidationAt,
            graceExpiresAt: graceExpiresAt,
            bundleUnlocked: false,
            entitlements: [.deepScan],
            customerEmail: "user@example.com",
            warningMessage: nil,
            activeLicenses: [
                ActivatedLicenseRecord(
                    id: "sale-1:sorty-deep-scan",
                    saleID: "sale-1",
                    keyHint: "ABCD...1234",
                    sku: .deepScan,
                    productName: "Deep Scan",
                    email: "user@example.com",
                    purchasedAt: Date(timeIntervalSince1970: 500)
                )
            ]
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct MockLicenseServiceClient: LicenseServiceClientProtocol {
    let requestHandler: @Sendable ([String], LicenseValidationReason) async throws -> LicenseEntitlementPayload

    func requestEntitlements(
        licenseKeys: [String],
        reason: LicenseValidationReason
    ) async throws -> LicenseEntitlementPayload {
        try await requestHandler(licenseKeys, reason)
    }
}

private final class InMemoryEntitlementSecretStore: EntitlementSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    func save(value: String, for key: String) -> Bool {
        lock.lock()
        storage[key] = value
        lock.unlock()
        return true
    }

    func loadValue(for key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func deleteValue(for key: String) -> Bool {
        lock.lock()
        storage.removeValue(forKey: key)
        lock.unlock()
        return true
    }
}

private final class GumroadStubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        let statusCode: Int
        let data: Data
    }

    nonisolated(unsafe) static var stub: Stub?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastRequestBody: Data?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastRequestBody = request.httpBody ?? Self.readBodyStream(request.httpBodyStream)
        guard let stub = Self.stub,
              let response = HTTPURLResponse(
                url: request.url!,
                statusCode: stub.statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBodyStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
