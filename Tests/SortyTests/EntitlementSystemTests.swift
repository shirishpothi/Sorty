import CryptoKit
import XCTest
@testable import SortyLib

final class EntitlementSystemTests: XCTestCase {
    func testMutableTrustAnchorOverridesAreDebugOnly() throws {
        let suiteName = "EntitlementSystemTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("https://defaults-attacker.test", forKey: LicenseServiceConfiguration.serviceURLDefaultsKey)
        defaults.set("defaults-attacker-key", forKey: LicenseServiceConfiguration.publicKeyPEMDefaultsKey)

        let bundleDirectory = try makeTemporaryDirectory()
            .appendingPathComponent("LicenseConfig.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.sorty.tests.license-config",
            "CFBundleName": "LicenseConfig",
            "CFBundlePackageType": "BNDL",
            LicenseServiceConfiguration.serviceURLInfoPlistKey: "https://licenses.sorty.test",
            LicenseServiceConfiguration.publicKeyPEMInfoPlistKey: "bundled-public-key",
            LicenseServiceConfiguration.keyIDInfoPlistKey: "bundled-key-id"
        ]
        XCTAssertTrue((info as NSDictionary).write(to: bundleDirectory.appendingPathComponent("Info.plist"), atomically: true))
        let bundle = try XCTUnwrap(Bundle(url: bundleDirectory))

        let environmentConfiguration = LicenseServiceConfiguration.current(
            userDefaults: defaults,
            bundle: bundle,
            environment: [
                "SORTY_LICENSE_SERVICE_URL": "https://environment-attacker.test",
                "SORTY_LICENSE_PUBLIC_KEY_PEM": "environment-attacker-key"
            ]
        )
        let defaultsConfiguration = LicenseServiceConfiguration.current(
            userDefaults: defaults,
            bundle: bundle,
            environment: [:]
        )

        #if DEBUG
        XCTAssertEqual(environmentConfiguration.baseURL, URL(string: "https://environment-attacker.test"))
        XCTAssertEqual(defaultsConfiguration.baseURL, URL(string: "https://defaults-attacker.test"))
        #else
        XCTAssertEqual(environmentConfiguration.baseURL, URL(string: "https://licenses.sorty.test"))
        XCTAssertEqual(environmentConfiguration.publicKeyPEM, "bundled-public-key")
        XCTAssertEqual(defaultsConfiguration.baseURL, URL(string: "https://licenses.sorty.test"))
        XCTAssertEqual(defaultsConfiguration.publicKeyPEM, "bundled-public-key")
        #endif
    }

    @MainActor
    func testPreviewEntitlementOverridesAreDebugOnly() async throws {
        let suiteName = "EntitlementSystemTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("bundle_unlocked", forKey: "entitlementPreviewState")
        let manager = EntitlementManager(
            userDefaults: defaults,
            configuration: makeConfiguration(publicKeyPEM: ""),
            secureStore: EntitlementSecureStore(
                rootDirectory: try makeTemporaryDirectory(),
                secretStore: InMemoryEntitlementSecretStore()
            )
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

    func testSignedVerifierAcceptsLocalSignatureAndSecureStoreEncryptsCache() throws {
        let privateKey = P256.Signing.PrivateKey()
        let payload = makePayload(
            nextValidationAt: Date().addingTimeInterval(3_600),
            graceExpiresAt: Date().addingTimeInterval(86_400)
        )
        let envelope = try makeEnvelope(payload: payload, privateKey: privateKey)
        let configuration = makeConfiguration(publicKeyPEM: privateKey.publicKey.pemRepresentation)
        let verifiedPayload = try SignedEntitlementVerifier(configuration: configuration).verify(envelope)
        XCTAssertEqual(verifiedPayload.entitlementSet, [.deepScan])

        let rootDirectory = try makeTemporaryDirectory()
        let secureStore = EntitlementSecureStore(
            rootDirectory: rootDirectory,
            secretStore: InMemoryEntitlementSecretStore()
        )
        XCTAssertTrue(secureStore.saveLicenseKeys(["alpha-key"]))
        try secureStore.saveCachedEnvelope(envelope)

        let encryptedContents = String(
            decoding: try Data(contentsOf: rootDirectory.appendingPathComponent("license-cache.enc")),
            as: UTF8.self
        )
        XCTAssertFalse(encryptedContents.contains("deep_scan"))
        XCTAssertEqual(secureStore.storedLicenseKeys(), ["alpha-key"])
        XCTAssertEqual(try secureStore.loadCachedEnvelope(), envelope)
    }

    @MainActor
    func testExpiredCachedPayloadUsesGraceOnlyWhenStatusIsActive() async throws {
        let now = Date()
        let privateKey = P256.Signing.PrivateKey()

        let activeManager = try makeCachedManager(
            status: .active,
            privateKey: privateKey,
            now: now
        )
        await activeManager.bootstrapIfNeeded()
        guard case .grace = activeManager.state else {
            return XCTFail("Expected grace state, got \(activeManager.state)")
        }

        let revokedManager = try makeCachedManager(
            status: .revoked,
            privateKey: privateKey,
            now: now
        )
        await revokedManager.bootstrapIfNeeded()
        guard case .expired(let entitlements) = revokedManager.state else {
            return XCTFail("Expected expired state, got \(revokedManager.state)")
        }
        XCTAssertEqual(entitlements, [.deepScan])
    }

    func testRemoteClientRejectsInsecureTransportAndHonorsPrivacyMode() async {
        let insecureClient = RemoteLicenseServiceClient(
            configuration: LicenseServiceConfiguration(
                baseURL: URL(string: "http://licenses.sorty.test"),
                publicKeyPEM: "pem",
                keyID: "test-key",
                validationInterval: 3_600,
                gracePeriod: 86_400,
                seatLimit: 3
            )
        )

        do {
            _ = try await insecureClient.requestEntitlements(
                licenseKeys: ["license"],
                device: testDevice,
                reason: .refresh
            )
            XCTFail("Expected insecure transport rejection")
        } catch let error as LicenseServiceError {
            XCTAssertEqual(
                error,
                .invalidConfiguration("Sorty's license service must use HTTPS unless it points to localhost or loopback.")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let suiteName = "EntitlementSystemTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: NetworkPrivacyPolicy.internetPrivacyModeKey)
        NetworkPrivacyPolicy.setTestDefaultsSuiteName(suiteName)
        defer {
            NetworkPrivacyPolicy.setTestDefaultsSuiteName(nil)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let privacyClient = RemoteLicenseServiceClient(
            configuration: makeConfiguration(publicKeyPEM: "pem")
        )
        do {
            _ = try await privacyClient.requestEntitlements(
                licenseKeys: ["license"],
                device: testDevice,
                reason: .refresh
            )
            XCTFail("Expected privacy mode rejection")
        } catch let error as LicenseServiceError {
            XCTAssertEqual(error, .invalidConfiguration(NetworkPrivacyPolicy.blockedMessage))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private var testDevice: LicenseDeviceIdentity {
        LicenseDeviceIdentity(deviceID: "device-1", deviceName: "Test Mac", appVersion: "1.0")
    }

    private func makeConfiguration(publicKeyPEM: String) -> LicenseServiceConfiguration {
        LicenseServiceConfiguration(
            baseURL: URL(string: "https://licenses.sorty.test"),
            publicKeyPEM: publicKeyPEM,
            keyID: "test-key",
            validationInterval: 3_600,
            gracePeriod: 86_400,
            seatLimit: 3
        )
    }

    @MainActor
    private func makeCachedManager(
        status: LicenseValidationStatus,
        privateKey: P256.Signing.PrivateKey,
        now: Date
    ) throws -> EntitlementManager {
        let rootDirectory = try makeTemporaryDirectory()
        let store = EntitlementSecureStore(
            rootDirectory: rootDirectory,
            secretStore: InMemoryEntitlementSecretStore()
        )
        var payload = makePayload(
            nextValidationAt: now.addingTimeInterval(-60),
            graceExpiresAt: now.addingTimeInterval(7_200),
            device: store.currentDeviceIdentity()
        )
        payload = LicenseEntitlementPayload(
            status: status,
            issuedAt: payload.issuedAt,
            validatedAt: payload.validatedAt,
            nextValidationAt: payload.nextValidationAt,
            graceExpiresAt: payload.graceExpiresAt,
            bundleUnlocked: payload.bundleUnlocked,
            entitlements: payload.entitlements,
            customerEmail: payload.customerEmail,
            warningMessage: payload.warningMessage,
            seatState: payload.seatState,
            activeLicenses: payload.activeLicenses
        )
        _ = store.saveLicenseKeys(["cached-license"])
        try store.saveCachedEnvelope(makeEnvelope(payload: payload, privateKey: privateKey))

        return EntitlementManager(
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!,
            configuration: makeConfiguration(publicKeyPEM: privateKey.publicKey.pemRepresentation),
            secureStore: store,
            serviceClient: MockLicenseServiceClient { _, _, _ in
                throw LicenseServiceError.server(statusCode: 503, message: "offline")
            },
            now: { now }
        )
    }

    private func makePayload(
        nextValidationAt: Date,
        graceExpiresAt: Date,
        device: LicenseDeviceIdentity? = nil
    ) -> LicenseEntitlementPayload {
        let device = device ?? testDevice
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
            seatState: LicenseSeatState(
                currentDeviceID: device.deviceID,
                currentDeviceName: device.deviceName,
                currentDeviceRegisteredAt: Date(timeIntervalSince1970: 1_500),
                activeSeatCount: 1,
                seatLimit: 3
            ),
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

    private func makeEnvelope(
        payload: LicenseEntitlementPayload,
        privateKey: P256.Signing.PrivateKey
    ) throws -> SignedEntitlementEnvelope {
        let payloadData = try JSONEncoder.licensePayloadEncoder.encode(payload)
        let signature = try privateKey.signature(for: payloadData)
        return SignedEntitlementEnvelope(
            algorithm: "ES256",
            keyID: "test-key",
            payload: payloadData.base64EncodedString(),
            signature: signature.derRepresentation.base64EncodedString()
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct MockLicenseServiceClient: LicenseServiceClientProtocol {
    let requestHandler: @Sendable ([String], LicenseDeviceIdentity, LicenseValidationReason) async throws -> SignedEntitlementEnvelope

    func requestEntitlements(
        licenseKeys: [String],
        device: LicenseDeviceIdentity,
        reason: LicenseValidationReason
    ) async throws -> SignedEntitlementEnvelope {
        try await requestHandler(licenseKeys, device, reason)
    }

    func deactivate(licenseKeys: [String], device: LicenseDeviceIdentity) async throws {}
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
