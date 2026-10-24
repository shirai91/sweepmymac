import CryptoKit
import Foundation

public enum UpdateSignature {
    public static let publicKeyInfoKey = "SweepUpdatePublicKey"
    public static let fileExtension = "sig"
    static let maximumSignatureFileSize = 4096

    public static func publicKey(base64: String) -> Curve25519.Signing.PublicKey? {
        Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
    }

    public static func signatureFileContents(for file: URL, privateKey: Curve25519.Signing.PrivateKey) throws -> String {
        try privateKey.signature(for: Data(contentsOf: file)).base64EncodedString() + "\n"
    }

    public static func verify(_ file: URL, signatureFileContents: Data, publicKey: Curve25519.Signing.PublicKey) throws {
        let text = String(decoding: signatureFileContents, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let signature = Data(base64Encoded: text), signature.count == 64 else { throw UpdateError.badUpdateSignature }
        guard publicKey.isValidSignature(signature, for: try Data(contentsOf: file, options: .mappedIfSafe)) else {
            throw UpdateError.badUpdateSignature
        }
    }
}
