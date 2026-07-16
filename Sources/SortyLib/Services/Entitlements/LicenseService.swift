import Foundation

public struct LicenseServiceConfiguration: Equatable, Sendable {
    public static let sortyProductID = "w0WiZtzKwIjM7_xdOTSi2g=="
    public static let sortyPurchaseURL = URL(string: "https://shirishpothi.gumroad.com/l/Sorty")!
    public static let gumroadVerificationURL = URL(string: "https://api.gumroad.com/v2/licenses/verify")!

    public let productID: String
    public let purchaseURL: URL
    public let verificationURL: URL
    public let validationInterval: TimeInterval
    public let gracePeriod: TimeInterval

    public init(
        productID: String,
        purchaseURL: URL,
        verificationURL: URL = LicenseServiceConfiguration.gumroadVerificationURL,
        validationInterval: TimeInterval,
        gracePeriod: TimeInterval
    ) {
        self.productID = productID
        self.purchaseURL = purchaseURL
        self.verificationURL = verificationURL
        self.validationInterval = validationInterval
        self.gracePeriod = gracePeriod
    }

    public var isConfigured: Bool {
        !productID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && purchaseURL.scheme == "https"
            && verificationURL.scheme == "https"
    }

    public static func current() -> LicenseServiceConfiguration {
        LicenseServiceConfiguration(
            productID: sortyProductID,
            purchaseURL: sortyPurchaseURL,
            validationInterval: 24 * 60 * 60,
            gracePeriod: 7 * 24 * 60 * 60
        )
    }
}

public enum LicenseValidationReason: String, Codable, CaseIterable, Sendable {
    case activate
    case refresh
    case restore
}

public enum LicenseValidationStatus: String, Codable, Sendable {
    case active
    case revoked
    case expired
}

public struct ActivatedLicenseRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let saleID: String
    public let keyHint: String
    public let sku: ProductSKU
    public let productName: String
    public let email: String?
    public let purchasedAt: Date?

    public init(
        id: String,
        saleID: String,
        keyHint: String,
        sku: ProductSKU,
        productName: String,
        email: String?,
        purchasedAt: Date?
    ) {
        self.id = id
        self.saleID = saleID
        self.keyHint = keyHint
        self.sku = sku
        self.productName = productName
        self.email = email
        self.purchasedAt = purchasedAt
    }
}

public struct LicenseEntitlementPayload: Codable, Equatable, Sendable {
    public let status: LicenseValidationStatus
    public let issuedAt: Date
    public let validatedAt: Date
    public let nextValidationAt: Date
    public let graceExpiresAt: Date
    public let bundleUnlocked: Bool
    public let entitlements: [ProductEntitlement]
    public let customerEmail: String?
    public let warningMessage: String?
    public let activeLicenses: [ActivatedLicenseRecord]

    public init(
        status: LicenseValidationStatus,
        issuedAt: Date,
        validatedAt: Date,
        nextValidationAt: Date,
        graceExpiresAt: Date,
        bundleUnlocked: Bool,
        entitlements: [ProductEntitlement],
        customerEmail: String?,
        warningMessage: String?,
        activeLicenses: [ActivatedLicenseRecord]
    ) {
        self.status = status
        self.issuedAt = issuedAt
        self.validatedAt = validatedAt
        self.nextValidationAt = nextValidationAt
        self.graceExpiresAt = graceExpiresAt
        self.bundleUnlocked = bundleUnlocked
        self.entitlements = entitlements
        self.customerEmail = customerEmail
        self.warningMessage = warningMessage
        self.activeLicenses = activeLicenses
    }

    public var entitlementSet: Set<ProductEntitlement> {
        Set(entitlements)
    }
}

public enum LicenseServiceError: LocalizedError, Equatable {
    case serviceUnavailable
    case invalidConfiguration(String)
    case invalidResponse
    case decodingFailed
    case rejected(String)
    case wrongProduct
    case inactivePurchase

    public var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "Gumroad license verification is unavailable. Try again in a moment."
        case .invalidConfiguration(let message):
            return message
        case .invalidResponse, .decodingFailed:
            return "Gumroad returned an unreadable license response. Try again."
        case .rejected(let message):
            return message
        case .wrongProduct:
            return "This license key belongs to a different Gumroad product."
        case .inactivePurchase:
            return "This Gumroad purchase is no longer active."
        }
    }
}

public protocol LicenseServiceClientProtocol: Sendable {
    func requestEntitlements(
        licenseKeys: [String],
        reason: LicenseValidationReason
    ) async throws -> LicenseEntitlementPayload
}

public struct GumroadLicenseServiceClient: LicenseServiceClientProtocol {
    private let configuration: LicenseServiceConfiguration
    private let session: URLSession
    private let now: @Sendable () -> Date

    public init(
        configuration: LicenseServiceConfiguration,
        session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.session = session
        self.now = now
    }

    public func requestEntitlements(
        licenseKeys: [String],
        reason: LicenseValidationReason
    ) async throws -> LicenseEntitlementPayload {
        guard configuration.isConfigured else {
            throw LicenseServiceError.serviceUnavailable
        }

        let keys = normalized(keys: licenseKeys)
        guard !keys.isEmpty else {
            throw LicenseServiceError.rejected("Enter the license key from your Gumroad receipt.")
        }

        let purchases = try await verify(keys: keys)
        let timestamp = now()
        let records = zip(keys, purchases).map { licenseKey, purchase in
            let saleID = purchase.saleID ?? "gumroad-\(Self.hashHint(licenseKey))"
            return ActivatedLicenseRecord(
                id: "\(saleID):\(ProductSKU.proBundle.rawValue)",
                saleID: saleID,
                keyHint: Self.mask(licenseKey),
                sku: .proBundle,
                productName: purchase.productName ?? ProductSKU.proBundle.displayName,
                email: purchase.email,
                purchasedAt: Self.parseDate(purchase.saleTimestamp ?? purchase.createdAt)
            )
        }

        return LicenseEntitlementPayload(
            status: .active,
            issuedAt: timestamp,
            validatedAt: timestamp,
            nextValidationAt: timestamp.addingTimeInterval(configuration.validationInterval),
            graceExpiresAt: timestamp.addingTimeInterval(configuration.gracePeriod),
            bundleUnlocked: true,
            entitlements: ProductEntitlement.allCases,
            customerEmail: purchases.compactMap(\.email).first,
            warningMessage: nil,
            activeLicenses: records
        )
    }

    private func verify(keys: [String]) async throws -> [GumroadPurchase] {
        var purchases: [GumroadPurchase] = []
        purchases.reserveCapacity(keys.count)

        for key in keys {
            purchases.append(try await verify(licenseKey: key))
        }

        return purchases
    }

    private func verify(licenseKey: String) async throws -> GumroadPurchase {
        let endpoint = configuration.verificationURL
        guard endpoint.scheme?.lowercased() == "https" else {
            throw LicenseServiceError.invalidConfiguration("Gumroad license verification must use HTTPS.")
        }
        guard NetworkPrivacyPolicy.isRequestAllowed(url: endpoint) else {
            throw LicenseServiceError.invalidConfiguration(NetworkPrivacyPolicy.blockedMessage)
        }

        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "product_id", value: configuration.productID),
            URLQueryItem(name: "license_key", value: licenseKey),
            URLQueryItem(name: "increment_uses_count", value: "false")
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(
            for: request,
            delegate: LicenseRedirectRejectingDelegate.shared
        )
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseServiceError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let failure = try? JSONDecoder().decode(GumroadFailureResponse.self, from: data) {
                throw LicenseServiceError.rejected(failure.message)
            }
            throw LicenseServiceError.rejected("Gumroad could not verify this license key.")
        }

        let verification: GumroadLicenseVerification
        do {
            verification = try JSONDecoder().decode(GumroadLicenseVerification.self, from: data)
        } catch {
            throw LicenseServiceError.decodingFailed
        }

        guard verification.success, let purchase = verification.purchase else {
            throw LicenseServiceError.rejected(verification.message ?? "Gumroad could not verify this license key.")
        }
        guard purchase.productID == configuration.productID else {
            throw LicenseServiceError.wrongProduct
        }
        guard purchase.isActive(at: now()) else {
            throw LicenseServiceError.inactivePurchase
        }
        return purchase
    }

    private func normalized(keys: [String]) -> [String] {
        var seen: Set<String> = []
        return keys.compactMap { key in
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    private static func mask(_ licenseKey: String) -> String {
        guard licenseKey.count > 8 else { return "****" }
        return "\(licenseKey.prefix(4))...\(licenseKey.suffix(4))"
    }

    private static func hashHint(_ licenseKey: String) -> String {
        String(licenseKey.unicodeScalars.reduce(into: UInt64(5_381)) { hash, scalar in
            hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }, radix: 16)
    }

    fileprivate static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct GumroadLicenseVerification: Decodable, Sendable {
    let success: Bool
    let message: String?
    let purchase: GumroadPurchase?
}

private struct GumroadPurchase: Decodable, Sendable {
    let productID: String
    let productName: String?
    let email: String?
    let refunded: Bool
    let disputed: Bool
    let chargebacked: Bool
    let subscriptionEndedAt: String?
    let subscriptionFailedAt: String?
    let saleID: String?
    let saleTimestamp: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case productName = "product_name"
        case email
        case refunded
        case disputed
        case chargebacked
        case subscriptionEndedAt = "subscription_ended_at"
        case subscriptionFailedAt = "subscription_failed_at"
        case saleID = "sale_id"
        case id
        case orderNumber = "order_number"
        case saleTimestamp = "sale_timestamp"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        productID = try container.decode(String.self, forKey: .productID)
        productName = try container.decodeIfPresent(String.self, forKey: .productName)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        refunded = try container.decodeIfPresent(Bool.self, forKey: .refunded) ?? false
        disputed = try container.decodeIfPresent(Bool.self, forKey: .disputed) ?? false
        chargebacked = try container.decodeIfPresent(Bool.self, forKey: .chargebacked) ?? false
        subscriptionEndedAt = try container.decodeIfPresent(String.self, forKey: .subscriptionEndedAt)
        subscriptionFailedAt = try container.decodeIfPresent(String.self, forKey: .subscriptionFailedAt)
        saleTimestamp = try container.decodeIfPresent(String.self, forKey: .saleTimestamp)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)

        if let value = try container.decodeIfPresent(String.self, forKey: .saleID) {
            saleID = value
        } else if let value = try container.decodeIfPresent(String.self, forKey: .id) {
            saleID = value
        } else if let value = try container.decodeIfPresent(Int.self, forKey: .orderNumber) {
            saleID = String(value)
        } else {
            saleID = nil
        }
    }

    func isActive(at now: Date) -> Bool {
        guard !refunded, !disputed, !chargebacked else { return false }
        if let endedAt = GumroadLicenseServiceClient.parseDate(subscriptionEndedAt), endedAt <= now {
            return false
        }
        if let failedAt = GumroadLicenseServiceClient.parseDate(subscriptionFailedAt), failedAt <= now {
            return false
        }
        return true
    }
}

private struct GumroadFailureResponse: Decodable, Sendable {
    let message: String
}

private final class LicenseRedirectRejectingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = LicenseRedirectRejectingDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

extension JSONEncoder {
    static var licensePayloadEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var licensePayloadDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
