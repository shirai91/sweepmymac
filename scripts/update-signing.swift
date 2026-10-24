import CryptoKit
import Foundation
import Security

let keychainService = "com.tungpham.sweep.update-signing"
let keychainAccount = "ed25519-private-key"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func keychainQuery() -> [String: Any] {
    [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: keychainAccount,
    ]
}

func storedPrivateKey() -> Curve25519.Signing.PrivateKey? {
    var query = keychainQuery()
    query[kSecReturnData as String] = true
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status != errSecItemNotFound else { return nil }
    guard status == errSecSuccess, let data = result as? Data else { fail("Keychain read failed (status \(status)).") }
    guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) else { fail("The Keychain item is not an Ed25519 key.") }
    return key
}

func requiredPrivateKey() -> Curve25519.Signing.PrivateKey {
    guard let key = storedPrivateKey() else {
        fail("No signing key in the Keychain. Run: swift scripts/update-signing.swift generate")
    }
    return key
}

func store(_ key: Curve25519.Signing.PrivateKey) {
    guard storedPrivateKey() == nil else { fail("A signing key is already in the Keychain. Sweep will not replace it.") }
    var item = keychainQuery()
    item[kSecValueData as String] = key.rawRepresentation
    item[kSecAttrLabel as String] = "Sweep update signing key"
    item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else { fail("Keychain write failed (status \(status)).") }
}

func publicKeyBase64(_ key: Curve25519.Signing.PrivateKey) -> String {
    key.publicKey.rawRepresentation.base64EncodedString()
}

func publicKey(fromBase64 text: String) -> Curve25519.Signing.PublicKey {
    guard let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PublicKey(rawRepresentation: data)
    else { fail("Not a valid Ed25519 public key: \(text)") }
    return key
}

func sign(_ path: String) {
    let file = URL(fileURLWithPath: path)
    let key = requiredPrivateKey()
    guard let data = try? Data(contentsOf: file) else { fail("Cannot read \(path).") }
    guard let signature = try? key.signature(for: data) else { fail("Signing failed.") }
    let output = file.appendingPathExtension("sig")
    do {
        try (signature.base64EncodedString() + "\n").write(to: output, atomically: true, encoding: .utf8)
    } catch {
        fail("Cannot write \(output.path): \(error.localizedDescription)")
    }
    print(output.path)
}

func verify(_ path: String, publicKeyText: String) {
    let file = URL(fileURLWithPath: path)
    guard let data = try? Data(contentsOf: file),
          let signatureText = try? String(contentsOf: file.appendingPathExtension("sig"), encoding: .utf8),
          let signature = Data(base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines))
    else { fail("Cannot read \(path) and its .sig file.") }
    guard publicKey(fromBase64: publicKeyText).isValidSignature(signature, for: data) else {
        fail("The signature of \(path) does not match the public key.")
    }
    print("Signature OK: \(path)")
}

func importPrivateKey() {
    guard let line = readLine(), let data = Data(base64Encoded: line.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data)
    else { fail("Paste the base64 private key on standard input.") }
    store(key)
    print(publicKeyBase64(key))
}

let usage = """
Usage: swift scripts/update-signing.swift <command>
  generate              Make a new key pair, store the private key in the Keychain, print the public key
  public-key            Print the public key of the stored private key
  sign <file>           Write <file>.sig with the stored private key
  verify <file> <key>   Check <file>.sig against a base64 public key
  export-private-key    Print the private key as base64, for a backup
  import-private-key    Read a base64 private key from standard input and store it
"""

let arguments = Array(CommandLine.arguments.dropFirst())
switch (arguments.first, arguments.count) {
case ("generate", 1):
    let key = Curve25519.Signing.PrivateKey()
    store(key)
    print(publicKeyBase64(key))
case ("public-key", 1):
    print(publicKeyBase64(requiredPrivateKey()))
case ("sign", 2):
    sign(arguments[1])
case ("verify", 3):
    verify(arguments[1], publicKeyText: arguments[2])
case ("export-private-key", 1):
    print(requiredPrivateKey().rawRepresentation.base64EncodedString())
case ("import-private-key", 1):
    importPrivateKey()
default:
    print(usage)
    exit(2)
}
