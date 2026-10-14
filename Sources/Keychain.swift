import Foundation
import Security

nonisolated func readKeychain(account: String) -> Data? {
    let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "dev.gustaf.crew",
        kSecAttrAccount: account,
        kSecUseDataProtectionKeychain: true,
        kSecReturnData: true,
        kSecMatchLimit: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
    return result as? Data
}

nonisolated func saveKeychain(_ data: Data, account: String) throws {
    let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "dev.gustaf.crew",
        kSecAttrAccount: account,
        kSecUseDataProtectionKeychain: true,
    ]
    let attributes: [CFString: Any] = [kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock]
    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    let status = updateStatus == errSecItemNotFound ? SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil) : updateStatus
    guard status == errSecSuccess else { throw HermesError.keychain(status) }
}

nonisolated func deleteKeychain(account: String) {
    let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "dev.gustaf.crew",
        kSecAttrAccount: account,
        kSecUseDataProtectionKeychain: true,
    ]
    SecItemDelete(query as CFDictionary)
}
