import Foundation

public enum ProductCapability: String, CaseIterable, Codable, Sendable {
    case organization
    case basicHistory
    case watchedFolders
    case multipleWatchedFolders
    case batchOrganization
    case deepScan
    case duplicateDetection
    case fileTagging
    case learnings
    case workspaceHealth
    case storageLocations
    case rawHistoryOutput

    public var displayName: String {
        switch self {
        case .organization:
            return "Core organization"
        case .basicHistory:
            return "Basic history"
        case .watchedFolders:
            return "Watched folders"
        case .multipleWatchedFolders:
            return "Multiple watched folders"
        case .batchOrganization:
            return "Batch organization"
        case .deepScan:
            return "Deep scan"
        case .duplicateDetection:
            return "Duplicate detection"
        case .fileTagging:
            return "Finder tagging"
        case .learnings:
            return "Learnings"
        case .workspaceHealth:
            return "Workspace Health"
        case .storageLocations:
            return "Storage locations"
        case .rawHistoryOutput:
            return "Raw history output"
        }
    }

    public var unlockSummary: String {
        switch self {
        case .organization, .basicHistory, .watchedFolders:
            return "This capability stays in Sorty's free core tier."
        case .multipleWatchedFolders:
            return "Free core includes one watched folder. Unlock more folders a la carte or with Sorty Pro."
        case .batchOrganization:
            return "Run multiple folders in one session with a dedicated batch unlock or the full Sorty Pro bundle."
        case .deepScan:
            return "Unlock content-aware deep scanning as a standalone feature or through Sorty Pro."
        case .duplicateDetection:
            return "Duplicate review is a paid feature, available individually or through Sorty Pro."
        case .fileTagging:
            return "Finder tagging is a paid enhancement, available individually or through Sorty Pro."
        case .learnings:
            return "Learnings is part of the paid capability set and can be unlocked individually or with Sorty Pro."
        case .workspaceHealth:
            return "Workspace Health is a paid capability, available individually or through Sorty Pro."
        case .storageLocations:
            return "Custom storage locations are part of the paid capability set."
        case .rawHistoryOutput:
            return "Extended history retention and raw output stay in paid tiers."
        }
    }

    public var systemImage: String {
        switch self {
        case .organization:
            return "folder.badge.gearshape"
        case .basicHistory, .rawHistoryOutput:
            return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .watchedFolders, .multipleWatchedFolders:
            return "eye"
        case .batchOrganization:
            return "square.stack.3d.up.fill"
        case .deepScan:
            return "doc.text.magnifyingglass"
        case .duplicateDetection:
            return "doc.on.doc"
        case .fileTagging:
            return "tag"
        case .learnings:
            return "brain"
        case .workspaceHealth:
            return "heart.text.square"
        case .storageLocations:
            return "externaldrive"
        }
    }
}

public enum ProductEntitlement: String, CaseIterable, Codable, Sendable, Hashable {
    case watchedFoldersPlus = "watched_folders_plus"
    case batchOrganization = "batch_organization"
    case deepScan = "deep_scan"
    case duplicateDetection = "duplicate_detection"
    case fileTagging = "file_tagging"
    case learnings = "learnings"
    case workspaceHealth = "workspace_health"
    case storageLocations = "storage_locations"
    case historyPlus = "history_plus"
    case premiumProviders = "premium_providers"

    public var displayName: String {
        switch self {
        case .watchedFoldersPlus:
            return "Watched Folders+"
        case .batchOrganization:
            return "Batch Organization"
        case .deepScan:
            return "Deep Scan"
        case .duplicateDetection:
            return "Duplicate Detection"
        case .fileTagging:
            return "Finder Tagging"
        case .learnings:
            return "Learnings"
        case .workspaceHealth:
            return "Workspace Health"
        case .storageLocations:
            return "Storage Locations"
        case .historyPlus:
            return "History+"
        case .premiumProviders:
            return "Premium Provider Pack"
        }
    }
}

public enum ProductSKU: String, CaseIterable, Codable, Sendable, Hashable {
    case watchedFoldersPlus = "sorty-watched-folders-plus"
    case batchOrganization = "sorty-batch-organization"
    case deepScan = "sorty-deep-scan"
    case duplicateDetection = "sorty-duplicate-detection"
    case fileTagging = "sorty-file-tagging"
    case learnings = "sorty-learnings"
    case workspaceHealth = "sorty-workspace-health"
    case storageLocations = "sorty-storage-locations"
    case historyPlus = "sorty-history-plus"
    case premiumProviders = "sorty-provider-pack"
    case proBundle = "sorty-pro-bundle"

    public var displayName: String {
        switch self {
        case .watchedFoldersPlus:
            return "Watched Folders+"
        case .batchOrganization:
            return "Batch Organization"
        case .deepScan:
            return "Deep Scan"
        case .duplicateDetection:
            return "Duplicate Detection"
        case .fileTagging:
            return "Finder Tagging"
        case .learnings:
            return "Learnings"
        case .workspaceHealth:
            return "Workspace Health"
        case .storageLocations:
            return "Storage Locations"
        case .historyPlus:
            return "History+"
        case .premiumProviders:
            return "Premium Provider Pack"
        case .proBundle:
            return "Sorty Pro"
        }
    }

    public var includedEntitlements: Set<ProductEntitlement> {
        switch self {
        case .watchedFoldersPlus:
            return [.watchedFoldersPlus]
        case .batchOrganization:
            return [.batchOrganization]
        case .deepScan:
            return [.deepScan]
        case .duplicateDetection:
            return [.duplicateDetection]
        case .fileTagging:
            return [.fileTagging]
        case .learnings:
            return [.learnings]
        case .workspaceHealth:
            return [.workspaceHealth]
        case .storageLocations:
            return [.storageLocations]
        case .historyPlus:
            return [.historyPlus]
        case .premiumProviders:
            return [.premiumProviders]
        case .proBundle:
            return Set(ProductEntitlement.allCases)
        }
    }
}

public enum EntitlementState: Equatable, Sendable {
    case unknown
    case free
    case partiallyUnlocked(Set<ProductEntitlement>)
    case bundleUnlocked
    case grace(previouslyUnlocked: Set<ProductEntitlement>, expiresAt: Date?)
    case expired(previouslyUnlocked: Set<ProductEntitlement>)
}

public struct EntitlementDefinition: Equatable, Sendable {
    public let entitlement: ProductEntitlement
    public let sku: ProductSKU
    public let title: String
    public let capabilities: Set<ProductCapability>

    public init(
        entitlement: ProductEntitlement,
        sku: ProductSKU,
        title: String,
        capabilities: Set<ProductCapability>
    ) {
        self.entitlement = entitlement
        self.sku = sku
        self.title = title
        self.capabilities = capabilities
    }
}

public struct EntitlementSnapshot: Equatable, Sendable {
    public let state: EntitlementState
    public let unlockedEntitlements: Set<ProductEntitlement>
    public let enabledCapabilities: Set<ProductCapability>
    public let maxWatchedFolders: Int
    public let accessPolicy: FreePlanAccessPolicy
    public let providerAccess: [AIProvider: Set<ProviderAuthMethod>]

    public init(
        state: EntitlementState,
        unlockedEntitlements: Set<ProductEntitlement>,
        enabledCapabilities: Set<ProductCapability>,
        maxWatchedFolders: Int,
        accessPolicy: FreePlanAccessPolicy,
        providerAccess: [AIProvider: Set<ProviderAuthMethod>]
    ) {
        self.state = state
        self.unlockedEntitlements = unlockedEntitlements
        self.enabledCapabilities = enabledCapabilities
        self.maxWatchedFolders = maxWatchedFolders
        self.accessPolicy = accessPolicy
        self.providerAccess = providerAccess
    }

    public func isEnabled(_ capability: ProductCapability) -> Bool {
        enabledCapabilities.contains(capability)
    }

    public func isProviderSelectable(_ provider: AIProvider) -> Bool {
        providerAccess[provider]?.isEmpty == false
    }

    public func supportedAuthMethods(for provider: AIProvider) -> [ProviderAuthMethod] {
        let allowedMethods = providerAccess[provider] ?? []
        return provider.supportedAuthMethods.filter { allowedMethods.contains($0) }
    }

    public func isProviderAllowed(_ provider: AIProvider, authMethod: ProviderAuthMethod) -> Bool {
        guard let allowedMethods = providerAccess[provider], !allowedMethods.isEmpty else {
            return false
        }
        return allowedMethods.contains(authMethod)
    }

    public var visibleProviders: [AIProvider] {
        AIProvider.allCases.filter(\.isAvailable)
    }

    public var availableProviders: [AIProvider] {
        visibleProviders.filter(isProviderSelectable)
    }

    public func providerRestrictionMessage(for provider: AIProvider, authMethod: ProviderAuthMethod? = nil) -> String {
        if provider == .openAI, authMethod == .accountSignIn {
            return "OpenAI Codex account sign-in is part of the paid provider pack. Switch OpenAI to API Key or unlock premium provider access."
        }

        if provider == .openAI {
            return "OpenAI stays available in free mode with an API key. Premium provider access unlocks extra auth paths and provider options."
        }

        return "\(provider.displayName) is part of Sorty's paid provider pack. Unlock premium provider access or Sorty Pro to use it."
    }

    public func sanitized(_ config: AIConfig) -> AIConfig {
        var sanitized = config

        if !isProviderSelectable(sanitized.provider),
           let fallbackProvider = availableProviders.first {
            sanitized.provider = fallbackProvider
            sanitized.apiURL = fallbackProvider.defaultAPIURL
            sanitized.model = fallbackProvider.defaultModel
            sanitized.requiresAPIKey = fallbackProvider.typicallyRequiresAPIKey
            sanitized.apiKey = nil
        }

        let selectedProvider = sanitized.provider
        let allowedAuthMethods = supportedAuthMethods(for: selectedProvider)
        if let preferredAuthMethod = allowedAuthMethods.first,
           !allowedAuthMethods.contains(sanitized.authMethod(for: selectedProvider)) {
            sanitized.setAuthMethod(preferredAuthMethod, for: selectedProvider)
            if preferredAuthMethod != .apiKey {
                sanitized.apiKey = nil
            }
        }

        sanitized.requiresAPIKey = selectedProvider.typicallyRequiresAPIKey

        if !isEnabled(.deepScan) || !selectedProvider.supportsDeepScan {
            sanitized.enableDeepScan = false
        }
        if !isEnabled(.duplicateDetection) {
            sanitized.detectDuplicates = false
            sanitized.storeDuplicateMetadata = false
        }
        if !isEnabled(.fileTagging) {
            sanitized.enableFileTagging = false
        }

        if isFreeTier {
            sanitized.maxTopLevelFolders = 10
            sanitized.enableSmartRename = false
            sanitized.enableVision = false
            sanitized.limitVisionImages = true
            sanitized.visionBatchSize = 5
            sanitized.namingStyle = .descriptive
            sanitized.customNamingInstructions = nil
            sanitized.selectedNamingPresetId = nil
        }

        if !allowsParameterTuning {
            sanitized.temperature = Self.defaultLockedTemperature
        }

        if !allowsDeveloperStats {
            sanitized.showStatsForNerds = false
        }

        if let automationProvider = sanitized.automationProvider,
           !isProviderAllowed(automationProvider, authMethod: sanitized.authMethod(for: automationProvider)) {
            sanitized.automationProvider = nil
            sanitized.automationModel = nil
        }

        if !allowsAutomationSeparateModelSelection {
            sanitized.automationProvider = nil
            sanitized.automationModel = nil
        }

        return sanitized
    }

    public var isFreeTier: Bool {
        accessPolicy.isFreeTier
    }

    public var maxStorageLocations: Int {
        accessPolicy.maxStorageLocations
    }

    public var maxLocalOrganizations: Int? {
        accessPolicy.maxLocalOrganizations
    }

    public var allowsParameterTuning: Bool {
        accessPolicy.allowsParameterTuning
    }

    public var allowsAutomationSeparateModelSelection: Bool {
        accessPolicy.allowsAutomationSeparateModelSelection
    }

    public var allowsLaunchAtLoginAutomation: Bool {
        accessPolicy.allowsLaunchAtLoginAutomation
    }

    public var allowsBackgroundAutomation: Bool {
        accessPolicy.allowsBackgroundAutomation
    }

    public var allowsAutomationNotifications: Bool {
        accessPolicy.allowsAutomationNotifications
    }

    public var allowsQuitWarnings: Bool {
        accessPolicy.allowsQuitWarnings
    }

    public var allowsFinderIntegration: Bool {
        accessPolicy.allowsFinderIntegration
    }

    public var allowsAdvancedNotificationControls: Bool {
        accessPolicy.allowsAdvancedNotificationControls
    }

    public var allowsDeveloperStats: Bool {
        accessPolicy.allowsDeveloperStats
    }

    public var allowsAutomationDeeplinks: Bool {
        accessPolicy.allowsAutomationDeeplinks
    }

    public var allowsExperimentalSettings: Bool {
        accessPolicy.allowsExperimentalSettings
    }

    public static let defaultLockedTemperature = 0.7
}

public struct FreePlanAccessPolicy: Equatable, Sendable {
    public let isFreeTier: Bool
    public let maxStorageLocations: Int
    public let maxLocalOrganizations: Int?
    public let allowsParameterTuning: Bool
    public let allowsAutomationSeparateModelSelection: Bool
    public let allowsLaunchAtLoginAutomation: Bool
    public let allowsBackgroundAutomation: Bool
    public let allowsAutomationNotifications: Bool
    public let allowsQuitWarnings: Bool
    public let allowsFinderIntegration: Bool
    public let allowsAdvancedNotificationControls: Bool
    public let allowsDeveloperStats: Bool
    public let allowsAutomationDeeplinks: Bool
    public let allowsExperimentalSettings: Bool

    public init(
        isFreeTier: Bool,
        maxStorageLocations: Int,
        maxLocalOrganizations: Int?,
        allowsParameterTuning: Bool,
        allowsAutomationSeparateModelSelection: Bool,
        allowsLaunchAtLoginAutomation: Bool,
        allowsBackgroundAutomation: Bool,
        allowsAutomationNotifications: Bool,
        allowsQuitWarnings: Bool,
        allowsFinderIntegration: Bool,
        allowsAdvancedNotificationControls: Bool,
        allowsDeveloperStats: Bool,
        allowsAutomationDeeplinks: Bool,
        allowsExperimentalSettings: Bool
    ) {
        self.isFreeTier = isFreeTier
        self.maxStorageLocations = maxStorageLocations
        self.maxLocalOrganizations = maxLocalOrganizations
        self.allowsParameterTuning = allowsParameterTuning
        self.allowsAutomationSeparateModelSelection = allowsAutomationSeparateModelSelection
        self.allowsLaunchAtLoginAutomation = allowsLaunchAtLoginAutomation
        self.allowsBackgroundAutomation = allowsBackgroundAutomation
        self.allowsAutomationNotifications = allowsAutomationNotifications
        self.allowsQuitWarnings = allowsQuitWarnings
        self.allowsFinderIntegration = allowsFinderIntegration
        self.allowsAdvancedNotificationControls = allowsAdvancedNotificationControls
        self.allowsDeveloperStats = allowsDeveloperStats
        self.allowsAutomationDeeplinks = allowsAutomationDeeplinks
        self.allowsExperimentalSettings = allowsExperimentalSettings
    }
}

public final class EntitlementCatalog: Sendable {
    public static let shared = EntitlementCatalog()

    public let aLaCarteDefinitions: [EntitlementDefinition] = [
        EntitlementDefinition(
            entitlement: .watchedFoldersPlus,
            sku: .watchedFoldersPlus,
            title: "Watched Folders+",
            capabilities: [.multipleWatchedFolders]
        ),
        EntitlementDefinition(
            entitlement: .batchOrganization,
            sku: .batchOrganization,
            title: "Batch Organization",
            capabilities: [.batchOrganization]
        ),
        EntitlementDefinition(
            entitlement: .deepScan,
            sku: .deepScan,
            title: "Deep Scan",
            capabilities: [.deepScan]
        ),
        EntitlementDefinition(
            entitlement: .duplicateDetection,
            sku: .duplicateDetection,
            title: "Duplicate Detection",
            capabilities: [.duplicateDetection]
        ),
        EntitlementDefinition(
            entitlement: .fileTagging,
            sku: .fileTagging,
            title: "Finder Tagging",
            capabilities: [.fileTagging]
        ),
        EntitlementDefinition(
            entitlement: .learnings,
            sku: .learnings,
            title: "Learnings",
            capabilities: [.learnings]
        ),
        EntitlementDefinition(
            entitlement: .workspaceHealth,
            sku: .workspaceHealth,
            title: "Workspace Health",
            capabilities: [.workspaceHealth]
        ),
        EntitlementDefinition(
            entitlement: .storageLocations,
            sku: .storageLocations,
            title: "Storage Locations",
            capabilities: [.storageLocations]
        ),
        EntitlementDefinition(
            entitlement: .historyPlus,
            sku: .historyPlus,
            title: "History+",
            capabilities: [.rawHistoryOutput]
        ),
        EntitlementDefinition(
            entitlement: .premiumProviders,
            sku: .premiumProviders,
            title: "Premium Provider Pack",
            capabilities: []
        )
    ]

    public var freeCoreCapabilities: Set<ProductCapability> {
        [.organization, .basicHistory, .watchedFolders]
    }

    public func primaryUnlock(for capability: ProductCapability) -> EntitlementDefinition? {
        aLaCarteDefinitions.first { $0.capabilities.contains(capability) }
    }

    public func snapshot(for state: EntitlementState) -> EntitlementSnapshot {
        let unlockedEntitlements = resolvedEntitlements(for: state)
        let enabledCapabilities = unlockedEntitlements.reduce(into: freeCoreCapabilities) { result, entitlement in
            if let definition = aLaCarteDefinitions.first(where: { $0.entitlement == entitlement }) {
                result.formUnion(definition.capabilities)
            }
        }
        let accessPolicy = accessPolicy(for: unlockedEntitlements)

        return EntitlementSnapshot(
            state: state,
            unlockedEntitlements: unlockedEntitlements,
            enabledCapabilities: enabledCapabilities,
            maxWatchedFolders: unlockedEntitlements.contains(.watchedFoldersPlus) ? .max : 1,
            accessPolicy: accessPolicy,
            providerAccess: providerAccess(for: unlockedEntitlements)
        )
    }

    private func resolvedEntitlements(for state: EntitlementState) -> Set<ProductEntitlement> {
        switch state {
        case .unknown, .free, .expired:
            return []
        case .partiallyUnlocked(let entitlements):
            return entitlements
        case .bundleUnlocked:
            return Set(ProductEntitlement.allCases)
        case .grace(let entitlements, _):
            return entitlements
        }
    }

    private func providerAccess(for entitlements: Set<ProductEntitlement>) -> [AIProvider: Set<ProviderAuthMethod>] {
        var access: [AIProvider: Set<ProviderAuthMethod>] = [
            .openAI: [.apiKey],
            .anthropic: [.apiKey],
            .gemini: [.apiKey],
            .appleFoundationModel: [.apiKey]
        ]

        if entitlements.contains(.premiumProviders) {
            access[.openAI] = Set(AIProvider.openAI.supportedAuthMethods)
            access[.githubCopilot] = [.apiKey]
            access[.groq] = [.apiKey]
            access[.openAICompatible] = [.apiKey]
            access[.openRouter] = [.apiKey]
            access[.ollama] = [.apiKey]
        }

        return access
    }

    private func accessPolicy(for entitlements: Set<ProductEntitlement>) -> FreePlanAccessPolicy {
        let isFreeTier = entitlements.isEmpty

        return FreePlanAccessPolicy(
            isFreeTier: isFreeTier,
            maxStorageLocations: isFreeTier ? 1 : .max,
            maxLocalOrganizations: isFreeTier ? 5 : nil,
            allowsParameterTuning: !isFreeTier,
            allowsAutomationSeparateModelSelection: !isFreeTier,
            allowsLaunchAtLoginAutomation: !isFreeTier,
            allowsBackgroundAutomation: !isFreeTier,
            allowsAutomationNotifications: !isFreeTier,
            allowsQuitWarnings: !isFreeTier,
            allowsFinderIntegration: !isFreeTier,
            allowsAdvancedNotificationControls: !isFreeTier,
            allowsDeveloperStats: !isFreeTier,
            allowsAutomationDeeplinks: !isFreeTier,
            allowsExperimentalSettings: !isFreeTier
        )
    }
}

private final class LockedEntitlementSnapshotStore: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot = EntitlementCatalog.shared.snapshot(for: .free)

    func currentSnapshot() -> EntitlementSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    func update(_ newSnapshot: EntitlementSnapshot) {
        lock.lock()
        snapshot = newSnapshot
        lock.unlock()
    }
}

public enum EntitlementRuntime {
    private static let storage = LockedEntitlementSnapshotStore()

    public static var currentSnapshot: EntitlementSnapshot {
        storage.currentSnapshot()
    }

    static func update(_ newSnapshot: EntitlementSnapshot) {
        storage.update(newSnapshot)
    }
}

@MainActor
public final class EntitlementManager: ObservableObject {
    public static let shared = EntitlementManager()

    @Published public private(set) var state: EntitlementState
    @Published public private(set) var snapshot: EntitlementSnapshot
    @Published public private(set) var activeLicenses: [ActivatedLicenseRecord]
    @Published public private(set) var customerEmail: String?
    @Published public private(set) var validatedAt: Date?
    @Published public private(set) var nextValidationAt: Date?
    @Published public private(set) var graceExpiresAt: Date?
    @Published public private(set) var warningMessage: String?
    @Published public private(set) var lastErrorMessage: String?
    @Published public private(set) var isSyncing = false
    @Published public private(set) var syncReason: LicenseValidationReason?

    private let userDefaults: UserDefaults
    private let configuration: LicenseServiceConfiguration
    private let secureStore: EntitlementSecureStore
    private let serviceClient: any LicenseServiceClientProtocol
    private let now: @Sendable () -> Date
    private let previewStateKey = "entitlementPreviewState"
    private let previewEntitlementsKey = "entitlementPreviewEntitlements"
    private let previewGraceExpiryKey = "entitlementPreviewGraceExpiry"
    private var cachedPayload: LicenseEntitlementPayload?
    private var hasBootstrapped = false

    public init(
        userDefaults: UserDefaults = .standard,
        configuration: LicenseServiceConfiguration = .current(),
        secureStore: EntitlementSecureStore = EntitlementSecureStore(),
        serviceClient: (any LicenseServiceClientProtocol)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.userDefaults = userDefaults
        self.configuration = configuration
        self.secureStore = secureStore
        self.serviceClient = serviceClient ?? GumroadLicenseServiceClient(configuration: configuration)
        self.now = now
        self.state = .unknown
        self.snapshot = EntitlementCatalog.shared.snapshot(for: .unknown)
        self.activeLicenses = []
        self.customerEmail = nil
        self.validatedAt = nil
        self.nextValidationAt = nil
        self.graceExpiresAt = nil
        self.warningMessage = nil
        self.lastErrorMessage = nil
        EntitlementRuntime.update(snapshot)

        if usesPreviewOverrides {
            refreshFromPreviewOverrides()
        } else {
            restoreCachedState()
        }
    }

    public var availableProviders: [AIProvider] {
        snapshot.availableProviders
    }

    public var visibleProviders: [AIProvider] {
        snapshot.visibleProviders
    }

    public var isServiceConfigured: Bool {
        configuration.isConfigured
    }

    public var purchaseURL: URL {
        configuration.purchaseURL
    }

    public var hasStoredPurchases: Bool {
        !secureStore.storedLicenseKeys().isEmpty
    }

    public func isEnabled(_ capability: ProductCapability) -> Bool {
        snapshot.isEnabled(capability)
    }

    public func supportedAuthMethods(for provider: AIProvider) -> [ProviderAuthMethod] {
        snapshot.supportedAuthMethods(for: provider)
    }

    public func isProviderSelectable(_ provider: AIProvider) -> Bool {
        snapshot.isProviderSelectable(provider)
    }

    public func providerRestrictionMessage(for provider: AIProvider, authMethod: ProviderAuthMethod? = nil) -> String {
        snapshot.providerRestrictionMessage(for: provider, authMethod: authMethod)
    }

    public var maxStorageLocations: Int {
        snapshot.maxStorageLocations
    }

    public var maxLocalOrganizations: Int? {
        snapshot.maxLocalOrganizations
    }

    public var isFreeTier: Bool {
        snapshot.isFreeTier
    }

    public var allowsParameterTuning: Bool {
        snapshot.allowsParameterTuning
    }

    public var allowsAutomationSeparateModelSelection: Bool {
        snapshot.allowsAutomationSeparateModelSelection
    }

    public var allowsLaunchAtLoginAutomation: Bool {
        snapshot.allowsLaunchAtLoginAutomation
    }

    public var allowsBackgroundAutomation: Bool {
        snapshot.allowsBackgroundAutomation
    }

    public var allowsAutomationNotifications: Bool {
        snapshot.allowsAutomationNotifications
    }

    public var allowsQuitWarnings: Bool {
        snapshot.allowsQuitWarnings
    }

    public var allowsFinderIntegration: Bool {
        snapshot.allowsFinderIntegration
    }

    public var allowsAdvancedNotificationControls: Bool {
        snapshot.allowsAdvancedNotificationControls
    }

    public var allowsDeveloperStats: Bool {
        snapshot.allowsDeveloperStats
    }

    public var allowsAutomationDeeplinks: Bool {
        snapshot.allowsAutomationDeeplinks
    }

    public var allowsExperimentalSettings: Bool {
        snapshot.allowsExperimentalSettings
    }

    public func refreshFromPreviewOverrides() {
        guard usesPreviewOverrides else { return }
        cachedPayload = nil
        activeLicenses = []
        customerEmail = nil
        validatedAt = nil
        nextValidationAt = nil
        graceExpiresAt = nil
        warningMessage = nil
        lastErrorMessage = nil
        apply(resolvePreviewState())
    }

    public func apply(_ newState: EntitlementState) {
        state = newState
        snapshot = EntitlementCatalog.shared.snapshot(for: newState)
        EntitlementRuntime.update(snapshot)
    }

    public func bootstrapIfNeeded() async {
        guard !usesPreviewOverrides else {
            refreshFromPreviewOverrides()
            return
        }

        if !hasBootstrapped {
            hasBootstrapped = true
            restoreCachedState()
        }

        if shouldRefreshEntitlements {
            await refreshEntitlements(force: true)
        } else if state == .unknown {
            apply(.free)
        }
    }

    @discardableResult
    public func activate(licenseKey: String) async -> Bool {
        let trimmed = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastErrorMessage = "Enter a Gumroad license key to activate Sorty."
            return false
        }

        return await syncEntitlements(with: [trimmed], reason: .activate)
    }

    @discardableResult
    public func restorePurchases() async -> Bool {
        let keys = secureStore.storedLicenseKeys()
        guard !keys.isEmpty else {
            lastErrorMessage = "No previous Sorty license keys were stored on this Mac to restore."
            return false
        }
        return await syncEntitlements(with: keys, reason: .restore)
    }

    @discardableResult
    public func refreshEntitlements(force: Bool = false) async -> Bool {
        let keys = secureStore.storedLicenseKeys()
        guard !keys.isEmpty else {
            if force {
                lastErrorMessage = "No active Sorty license keys are stored on this Mac."
            }
            if state == .unknown {
                apply(.free)
            }
            return false
        }

        guard force || shouldRefreshEntitlements else {
            return true
        }

        return await syncEntitlements(with: keys, reason: .refresh)
    }

    @discardableResult
    public func removeLicense() async -> Bool {
        let keys = secureStore.storedLicenseKeys()
        guard !keys.isEmpty else {
            do {
                try secureStore.clearAll()
            } catch {
                lastErrorMessage = error.localizedDescription
                return false
            }
            clearRuntimeLicenseMetadata()
            apply(.free)
            return true
        }

        isSyncing = true
        syncReason = nil
        lastErrorMessage = nil

        defer {
            isSyncing = false
            syncReason = nil
        }

        do {
            try secureStore.clearAll()
            clearRuntimeLicenseMetadata()
            apply(.free)
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private func resolvePreviewState() -> EntitlementState {
        guard Self.allowsPreviewOverrides else { return .free }
        guard let rawState = userDefaults.string(forKey: previewStateKey)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !rawState.isEmpty else {
            return .free
        }

        let entitlements = Set(
            (userDefaults.array(forKey: previewEntitlementsKey) as? [String] ?? [])
                .compactMap(ProductEntitlement.init(rawValue:))
        )
        let graceExpiry = userDefaults.object(forKey: previewGraceExpiryKey) as? Date

        switch rawState {
        case "unknown":
            return .unknown
        case "free":
            return .free
        case "partial", "partially_unlocked":
            return .partiallyUnlocked(entitlements)
        case "bundle", "bundle_unlocked", "pro":
            return .bundleUnlocked
        case "grace":
            return .grace(previouslyUnlocked: entitlements.isEmpty ? Set(ProductEntitlement.allCases) : entitlements, expiresAt: graceExpiry)
        case "expired":
            return .expired(previouslyUnlocked: entitlements)
        default:
            return .free
        }
    }

    private var usesPreviewOverrides: Bool {
        guard Self.allowsPreviewOverrides else { return false }
        return userDefaults.object(forKey: previewStateKey) != nil
    }

    private static var allowsPreviewOverrides: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private var shouldRefreshEntitlements: Bool {
        guard configuration.isConfigured else { return false }
        guard !secureStore.storedLicenseKeys().isEmpty else { return false }
        guard let nextValidationAt else { return true }
        return nextValidationAt <= now()
    }

    private func syncEntitlements(
        with licenseKeys: [String],
        reason: LicenseValidationReason
    ) async -> Bool {
        guard configuration.isConfigured else {
            lastErrorMessage = LicenseServiceError.serviceUnavailable.localizedDescription
            return false
        }

        isSyncing = true
        syncReason = reason
        lastErrorMessage = nil

        defer {
            isSyncing = false
            syncReason = nil
        }

        do {
            let payload = try await serviceClient.requestEntitlements(
                licenseKeys: licenseKeys,
                reason: reason
            )
            guard secureStore.saveLicenseKeys(licenseKeys) else {
                throw EntitlementSecureStoreError.keychainSaveFailed
            }
            try secureStore.saveCachedPayload(payload)
            applyValidatedPayload(payload)
            return true
        } catch {
            if reason != .activate {
                applyGraceStateIfPossible(after: error)
            }
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    private func restoreCachedState() {
        do {
            guard let payload = try secureStore.loadCachedPayload() else {
                apply(.free)
                return
            }

            cachedPayload = payload
            if payload.nextValidationAt <= now() {
                applyGraceOrActiveState(from: payload)
            } else {
                applyValidatedPayload(payload)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            apply(.free)
        }
    }

    private func applyValidatedPayload(_ payload: LicenseEntitlementPayload) {
        cachedPayload = payload
        activeLicenses = payload.activeLicenses
        customerEmail = payload.customerEmail
        validatedAt = payload.validatedAt
        nextValidationAt = payload.nextValidationAt
        graceExpiresAt = payload.graceExpiresAt
        warningMessage = payload.warningMessage
        lastErrorMessage = nil
        apply(state(from: payload))
    }

    private func applyGraceStateIfPossible(after error: Error) {
        let payload = cachedPayload ?? loadCachedPayloadForGrace()
        guard let payload else {
            apply(.free)
            return
        }

        cachedPayload = payload
        activeLicenses = payload.activeLicenses
        customerEmail = payload.customerEmail
        validatedAt = payload.validatedAt
        nextValidationAt = payload.nextValidationAt
        graceExpiresAt = payload.graceExpiresAt
        warningMessage = payload.warningMessage ?? error.localizedDescription
        applyGraceOrActiveState(from: payload)
    }

    private func applyGraceOrActiveState(from payload: LicenseEntitlementPayload) {
        let entitlements = payload.bundleUnlocked ? Set(ProductEntitlement.allCases) : payload.entitlementSet
        if payload.status == .active, payload.graceExpiresAt > now() {
            apply(.grace(previouslyUnlocked: entitlements, expiresAt: payload.graceExpiresAt))
        } else {
            apply(.expired(previouslyUnlocked: entitlements))
        }
    }

    private func loadCachedPayloadForGrace() -> LicenseEntitlementPayload? {
        try? secureStore.loadCachedPayload()
    }

    private func clearRuntimeLicenseMetadata() {
        cachedPayload = nil
        activeLicenses = []
        customerEmail = nil
        validatedAt = nil
        nextValidationAt = nil
        graceExpiresAt = nil
        warningMessage = nil
        lastErrorMessage = nil
    }

    private func state(from payload: LicenseEntitlementPayload) -> EntitlementState {
        let entitlements = payload.bundleUnlocked ? Set(ProductEntitlement.allCases) : payload.entitlementSet

        switch payload.status {
        case .active:
            if payload.bundleUnlocked {
                return .bundleUnlocked
            }
            return entitlements.isEmpty ? .free : .partiallyUnlocked(entitlements)
        case .revoked, .expired:
            return .expired(previouslyUnlocked: entitlements)
        }
    }
}

public extension AIConfig {
    func applyingEntitlements(_ snapshot: EntitlementSnapshot = EntitlementRuntime.currentSnapshot) -> AIConfig {
        snapshot.sanitized(self)
    }
}

public extension AppState.AppView {
    var requiredCapability: ProductCapability? {
        switch self {
        case .duplicates:
            return .duplicateDetection
        case .learnings:
            return .learnings
        case .settings, .organize, .history, .exclusions, .watchedFolders:
            return nil
        }
    }
}

public extension DeeplinkDestination {
    var requiredCapability: ProductCapability? {
        switch self {
        case .duplicates:
            return .duplicateDetection
        case .learnings:
            return .learnings
        case .organize, .settings, .help, .open, .history, .persona, .watched, .rules, .exclusions, .exclude, .storage:
            return nil
        }
    }
}
