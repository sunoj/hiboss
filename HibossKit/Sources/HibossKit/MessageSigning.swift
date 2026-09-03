// Builds ES256 JWS boss messages and keeps private keys inside Secure Enclave.
// Exports pairing registration, signer persistence shape, and JWS construction.
// Depends on CryptoKit Secure Enclave and Foundation Codable.

import CryptoKit
import Foundation

public enum SigningClientKind: String, Codable, Sendable {
    case ios
    case macos
}

public enum MessageSigningError: Error, LocalizedError, Sendable {
    case secureEnclaveUnavailable

    public var errorDescription: String? {
        switch self {
        case .secureEnclaveUnavailable:
            "Secure Enclave is unavailable on this device."
        }
    }
}

public protocol BossMessageSignatureProvider: Sendable {
    var keyID: String { get }
    var bossID: String { get }
    func signature(for data: Data) throws -> Data
}

public struct PairingSigningRegistration: Encodable, Sendable {
    public let algorithm: String
    public let clientKind: SigningClientKind
    public let publicKey: String
    public let proof: String

    enum CodingKeys: String, CodingKey {
        case algorithm
        case clientKind = "client_kind"
        case publicKey = "public_key"
        case proof
    }
}

public struct PendingSecureEnclaveSigner: Sendable {
    private let keyRepresentation: Data
    public let clientKind: SigningClientKind
    public let publicKey: String

    private init(
        keyRepresentation: Data,
        clientKind: SigningClientKind,
        publicKey: String
    ) {
        self.keyRepresentation = keyRepresentation
        self.clientKind = clientKind
        self.publicKey = publicKey
    }

    public static func create(clientKind: SigningClientKind) throws -> Self {
        guard SecureEnclave.isAvailable else {
            throw MessageSigningError.secureEnclaveUnavailable
        }
        let key = try SecureEnclave.P256.Signing.PrivateKey(compactRepresentable: false)
        return Self(
            keyRepresentation: key.dataRepresentation,
            clientKind: clientKind,
            publicKey: key.publicKey.x963Representation.base64URLEncodedString()
        )
    }

    public func registration(pairingCode: String) throws -> PairingSigningRegistration {
        let input = Data("hiboss-pair-v1\n\(pairingCode)\n\(clientKind.rawValue)\n\(publicKey)".utf8)
        let key = try SecureEnclave.P256.Signing.PrivateKey(
            dataRepresentation: keyRepresentation
        )
        let proof = try key.signature(for: input).rawRepresentation.base64URLEncodedString()
        return PairingSigningRegistration(
            algorithm: "ES256",
            clientKind: clientKind,
            publicKey: publicKey,
            proof: proof
        )
    }

    public func bind(bossID: String, keyID: String) -> SecureEnclaveMessageSigner {
        SecureEnclaveMessageSigner(
            keyRepresentation: keyRepresentation,
            keyID: keyID,
            bossID: bossID,
            clientKind: clientKind
        )
    }
}

public struct SecureEnclaveMessageSigner: BossMessageSignatureProvider, Codable, Sendable {
    private let keyRepresentation: Data
    public let keyID: String
    public let bossID: String
    public let clientKind: SigningClientKind

    init(
        keyRepresentation: Data,
        keyID: String,
        bossID: String,
        clientKind: SigningClientKind
    ) {
        self.keyRepresentation = keyRepresentation
        self.keyID = keyID
        self.bossID = bossID
        self.clientKind = clientKind
    }

    public func signature(for data: Data) throws -> Data {
        let key = try SecureEnclave.P256.Signing.PrivateKey(
            dataRepresentation: keyRepresentation
        )
        return try key.signature(for: data).rawRepresentation
    }
}

public enum BossMessageJWS {
    public static func signedReply(
        body: String,
        parentMessageID: String,
        provider: any BossMessageSignatureProvider,
        issuedAt: Date = Date(),
        messageID: UUID = UUID()
    ) throws -> String {
        let header = JWSHeader(alg: "ES256", kid: provider.keyID, typ: "hiboss-message+jws")
        let payload = SignedPayload(
            version: 1,
            purpose: "hiboss.boss-message",
            messageID: messageID.uuidString.lowercased(),
            issuedAt: Int(issuedAt.timeIntervalSince1970),
            bossID: provider.bossID,
            action: SignedAction(kind: "reply", messageID: parentMessageID),
            body: body
        )
        let encoder = JSONEncoder()
        let encodedHeader = try encoder.encode(header).base64URLEncodedString()
        let encodedPayload = try encoder.encode(payload).base64URLEncodedString()
        let input = "\(encodedHeader).\(encodedPayload)"
        let signature = try provider.signature(for: Data(input.utf8)).base64URLEncodedString()
        return "\(input).\(signature)"
    }
}

private struct JWSHeader: Encodable {
    let alg: String
    let kid: String
    let typ: String
}

private struct SignedAction: Encodable {
    let kind: String
    let messageID: String

    enum CodingKeys: String, CodingKey {
        case kind
        case messageID = "message_id"
    }
}

private struct SignedPayload: Encodable {
    let version: Int
    let purpose: String
    let messageID: String
    let issuedAt: Int
    let bossID: String
    let action: SignedAction
    let body: String

    enum CodingKeys: String, CodingKey {
        case version, purpose, action, body
        case messageID = "message_id"
        case issuedAt = "issued_at"
        case bossID = "boss_id"
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
