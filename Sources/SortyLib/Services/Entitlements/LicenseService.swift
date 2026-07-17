import Foundation
import CryptoKit

public struct LicenseServiceConfiguration: Equatable, Sendable {
    public static let serviceURLDefaultsKey = "sortyLicenseServiceURL"
    public static let publicKeyPEMDefaultsKey = "sortyLicensePublicKeyPEM"
    public static let keyIDDefaultsKey = "sortyLicensePublicKeyID"
    public static let validationHoursDefaultsKey = "sortyLicenseValidationHours"
    public static let graceHoursDefaultsKey = "sortyLicenseGraceHours"
    public static let seatLimitDefaultsKey = "sortyLicenseSeatLimit"
    public static let serviceURLInfoPlistKey = "SortyLicenseServiceURL"
    public static let publicKeyPEMInfoPlistKey = "SortyLicensePublicKeyPEM"
    public static let keyIDInfoPlistKey = "SortyLicensePublicKeyID"
    public static let validationHoursInfoPlistKey = "SortyLicenseValidationHours"
    public static let graceHoursInfoPlistKey = "SortyLicenseGraceHours"
    public static let seatLimitInfoPlistKey = "SortyLicenseSeatLimit"

    public let baseURL: URL?
    public let publicKeyPEM: String
    public let keyID: String
    public let validationInterval: TimeInterval
    public let gracePeriod: TimeInterval
    public let seatLimit: Int

    public init(
        baseURL: URL?,
        publicKeyPEM: String,
        keyID: String,
        validationInterval: TimeInterval,
        gracePeriod: TimeInterval,
        seatLimit: Int
    ) {
        self.baseURL = baseURL
        self.publicKeyPEM = publicKeyPEM
        self.keyID = keyID
        self.validationInterval = validationInterval
        self.gracePeriod = gracePeriod
        self.seatLimit = seatLimit
    }

    public var isConfigured: Bool {
        baseURL != nil && !publicKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func current(
        userDefaults: UserDefaults = .standard,
        processInfo: ProcessInfo = .processInfo,
        bundle: Bundle = .main,
        environment: [String: String]? = nil
    ) -> LicenseServiceConfiguration {
        func cleaned(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard trimmed != "$(inherited)",
                  !(trimmed.hasPrefix("$(") && trimmed.hasSuffix(")")) else {
                return nil
            }
            return trimmed
        }

        func env(_ key: String) -> String? {
            guard Self.allowsEnvironmentOverridesInCurrentBuild else { return nil }
            return cleaned(environment?[key] ?? processInfo.environment[key])
        }

        func defaults(_ key: String) -> String? {
            guard Self.allowsUserDefaultsOverridesInCurrentBuild else { return nil }
            return cleaned(userDefaults.string(forKey: key))
        }

        func bundleValue(_ key: String) -> String? {
            if let stringValue = bundle.object(forInfoDictionaryKey: key) as? String {
                return cleaned(stringValue)
            }
            if let numericValue = bundle.object(forInfoDictionaryKey: key) as? NSNumber {
                return cleaned(numericValue.stringValue)
            }
            return nil
        }

        func normalizedPEM(_ value: String?) -> String {
            guard let value = cleaned(value) else { return "" }
            return value.replacingOccurrences(of: "\\n", with: "\n")
        }

        let urlString = env("SORTY_LICENSE_SERVICE_URL")
            ?? defaults(serviceURLDefaultsKey)
            ?? bundleValue(serviceURLInfoPlistKey)
        let publicKeyPEM = normalizedPEM(
            env("SORTY_LICENSE_PUBLIC_KEY_PEM")
                ?? defaults(publicKeyPEMDefaultsKey)
                ?? bundleValue(publicKeyPEMInfoPlistKey)
        )
        let keyID = env("SORTY_LICENSE_PUBLIC_KEY_ID")
            ?? defaults(keyIDDefaultsKey)
            ?? bundleValue(keyIDInfoPlistKey)
            ?? "sorty-license-key-v1"

        let validationHours = Double(
            env("SORTY_LICENSE_VALIDATION_HOURS")
                ?? defaults(validationHoursDefaultsKey)
                ?? bundleValue(validationHoursInfoPlistKey)
                ?? ""
        ) ?? 24
        let graceHours = Double(
            env("SORTY_LICENSE_GRACE_HOURS")
                ?? defaults(graceHoursDefaultsKey)
                ?? bundleValue(graceHoursInfoPlistKey)
                ?? ""
        ) ?? 168
        let seatLimit = Int(
            env("SORTY_LICENSE_SEAT_LIMIT")
                ?? defaults(seatLimitDefaultsKey)
                ?? bundleValue(seatLimitInfoPlistKey)
                ?? ""
        ) ?? 3

        return LicenseServiceConfiguration(
            baseURL: urlString.flatMap(URL.init(string:)),
            publicKeyPEM: publicKeyPEM,
            keyID: keyID,
            validationInterval: validationHours * 3600,
            gracePeriod: graceHours * 3600,
            seatLimit: seatLimit
        )
    }

    private static var allowsUserDefaultsOverridesInCurrentBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static var allowsEnvironmentOverridesInCurrentBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
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

public struct LicenseDeviceIdentity: Codable, Equatable, Sendable {
    public let deviceID: String
    public let deviceName: String
    public let appVersion: String

    public init(deviceID: String, deviceName: String, appVersion: String) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.appVersion = appVersion
    }
}

public struct LicenseSeatState: Codable, Equatable, Sendable {
    public let currentDeviceID: String
    public let currentDeviceName: String
    public let currentDeviceRegisteredAt: Date?
    public let activeSeatCount: Int
    public let seatLimit: Int

    public init(
        currentDeviceID: String,
        currentDeviceName: String,
        currentDeviceRegisteredAt: Date?,
        activeSeatCount: Int,
        seatLimit: Int
    ) {
        self.currentDeviceID = currentDeviceID
        self.currentDeviceName = currentDeviceName
        self.currentDeviceRegisteredAt = currentDeviceRegisteredAt
        self.activeSeatCount = activeSeatCount
        self.seatLimit = seatLimit
    }
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
    public let seatState: LicenseSeatState
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
        seatState: LicenseSeatState,
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
        self.seatState = seatState
        self.activeLicenses = activeLicenses
    }

    public var entitlementSet: Set<ProductEntitlement> {
        Set(entitlements)
    }
}

public struct SignedEntitlementEnvelope: Codable, Equatable, Sendable {
    public let algorithm: String
    public let keyID: String
    public let payload: String
    public let signature: String

    public init(algorithm: String, keyID: String, payload: String, signature: String) {
        self.algorithm = algorithm
        self.keyID = keyID
        self.payload = payload
        self.signature = signature
    }
}

public struct LicenseEntitlementEnvelopeResponse: Codable, Sendable {
    public let envelope: SignedEntitlementEnvelope

    public init(envelope: SignedEntitlementEnvelope) {
        self.envelope = envelope
    }
}

public struct LicenseActivationRequest: Codable, Sendable {
    public let licenseKeys: [String]
    public let device: LicenseDeviceIdentity
    public let reason: LicenseValidationReason

    public init(licenseKeys: [String], device: LicenseDeviceIdentity, reason: LicenseValidationReason) {
        self.licenseKeys = licenseKeys
        self.device = device
        self.reason = reason
    }
}

public struct LicenseDeactivationRequest: Codable, Sendable {
    public let licenseKeys: [String]
    public let deviceID: String

    public init(licenseKeys: [String], deviceID: String) {
        self.licenseKeys = licenseKeys
        self.deviceID = deviceID
    }
}

public struct LicenseServiceErrorPayload: Codable, Sendable {
    public let error: String
    public let code: String?
    public let detail: String?

    public init(error: String, code: String?, detail: String?) {
        self.error = error
        self.code = code
        self.detail = detail
    }
}

public enum LicenseServiceError: LocalizedError, Equatable {
    case serviceUnavailable
    case invalidConfiguration(String)
    case invalidResponse
    case decodingFailed
    case signatureVerificationFailed(String)
    case server(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "Sorty's license verification service is not configured in this build yet."
        case .invalidConfiguration(let message):
            return message
        case .invalidResponse:
            return "The license verification service returned an invalid response."
        case .decodingFailed:
            return "Sorty couldn't decode the license response from the verification service."
        case .signatureVerificationFailed(let message):
            return message
        case .server(_, let message):
            return message
        }
    }
}

public protocol LicenseServiceClientProtocol: Sendable {
    func requestEntitlements(
        licenseKeys: [String],
        device: LicenseDeviceIdentity,
        reason: LicenseValidationReason
    ) async throws -> SignedEntitlementEnvelope

    func deactivate(
        licenseKeys: [String],
        device: LicenseDeviceIdentity
    ) async throws
}

public struct RemoteLicenseServiceClient: LicenseServiceClientProtocol {
    private let configuration: LicenseServiceConfiguration
    private let session: URLSession

    public init(
        configuration: LicenseServiceConfiguration,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    public func requestEntitlements(
        licenseKeys: [String],
        device: LicenseDeviceIdentity,
        reason: LicenseValidationReason
    ) async throws -> SignedEntitlementEnvelope {
        let requestBody = LicenseActivationRequest(
            licenseKeys: licenseKeys,
            device: device,
            reason: reason
        )
        let endpoint = reason == .activate ? "v1/activate" : "v1/refresh"
        let response: LicenseEntitlementEnvelopeResponse = try await send(
            requestBody,
            path: endpoint,
            expecting: LicenseEntitlementEnvelopeResponse.self
        )
        return response.envelope
    }

    public func deactivate(
        licenseKeys: [String],
        device: LicenseDeviceIdentity
    ) async throws {
        let requestBody = LicenseDeactivationRequest(
            licenseKeys: licenseKeys,
            deviceID: device.deviceID
        )
        let _: EmptyLicenseServiceResponse = try await send(
            requestBody,
            path: "v1/deactivate",
            expecting: EmptyLicenseServiceResponse.self
        )
    }

    private func send<RequestBody: Encodable, ResponseBody: Decodable>(
        _ body: RequestBody,
        path: String,
        expecting responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        guard let baseURL = configuration.baseURL else {
            throw LicenseServiceError.serviceUnavailable
        }

        let endpoint = baseURL.appendingPathComponent(path)
        try validate(endpoint: endpoint)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.licensePayloadEncoder.encode(body)

        let (data, response) = try await session.data(
            for: request,
            delegate: LicenseRedirectRejectingDelegate.shared
        )
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseServiceError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let errorPayload = try? JSONDecoder.licensePayloadDecoder.decode(LicenseServiceErrorPayload.self, from: data) {
                let message = errorPayload.detail ?? errorPayload.error
                throw LicenseServiceError.server(statusCode: httpResponse.statusCode, message: message)
            }

            let fallbackMessage = String(data: data, encoding: .utf8) ?? "The license service returned HTTP \(httpResponse.statusCode)."
            throw LicenseServiceError.server(statusCode: httpResponse.statusCode, message: fallbackMessage)
        }

        do {
            return try JSONDecoder.licensePayloadDecoder.decode(responseType, from: data)
        } catch {
            throw LicenseServiceError.decodingFailed
        }
    }

    private func validate(endpoint: URL) throws {
        guard let scheme = endpoint.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw LicenseServiceError.invalidConfiguration(
                "Sorty's license service URL must use http or https."
            )
        }

        guard NetworkPrivacyPolicy.isRequestAllowed(url: endpoint) else {
            throw LicenseServiceError.invalidConfiguration(NetworkPrivacyPolicy.blockedMessage)
        }

        if scheme != "https" && !NetworkPrivacyPolicy.isLoopbackURL(endpoint) {
            throw LicenseServiceError.invalidConfiguration(
                "Sorty's license service must use HTTPS unless it points to localhost or loopback."
            )
        }
    }
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

private struct EmptyLicenseServiceResponse: Codable, Sendable {}

public struct SignedEntitlementVerifier: Sendable {
    private let publicKey: P256.Signing.PublicKey
    private let expectedKeyID: String

    public init(configuration: LicenseServiceConfiguration) throws {
        guard configuration.isConfigured else {
            throw LicenseServiceError.serviceUnavailable
        }
        self.publicKey = try P256.Signing.PublicKey(pemRepresentation: configuration.publicKeyPEM)
        self.expectedKeyID = configuration.keyID
    }

    public func verify(_ envelope: SignedEntitlementEnvelope) throws -> LicenseEntitlementPayload {
        guard envelope.algorithm.uppercased() == "ES256" else {
            throw LicenseServiceError.signatureVerificationFailed(
                "Sorty received an unsupported license signature algorithm: \(envelope.algorithm)."
            )
        }

        guard envelope.keyID == expectedKeyID else {
            throw LicenseServiceError.signatureVerificationFailed(
                "Sorty received a license payload signed with an unexpected key identifier."
            )
        }

        guard let payloadData = Data(base64Encoded: envelope.payload),
              let signatureData = Data(base64Encoded: envelope.signature) else {
            throw LicenseServiceError.signatureVerificationFailed(
                "Sorty couldn't decode the signed entitlement payload."
            )
        }

        let signature = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
        guard publicKey.isValidSignature(signature, for: payloadData) else {
            throw LicenseServiceError.signatureVerificationFailed(
                "The signed entitlement payload failed local signature verification."
            )
        }

        do {
            return try JSONDecoder.licensePayloadDecoder.decode(LicenseEntitlementPayload.self, from: payloadData)
        } catch {
            throw LicenseServiceError.signatureVerificationFailed(
                "The signed entitlement payload passed signature checks but could not be decoded."
            )
        }
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
