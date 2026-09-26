import Foundation
import Security

/// Stores the Anthropic API key in the Keychain.
/// Query shape and update-then-add upsert follow Anthropic's ClaudeForFoundationModels
/// Sources/ClaudeForFoundationModels/AppAttestStore.swift; the account name follows
/// theJayTea/WritingTools macOS/WritingTools/App/KeychainManager.swift.
struct APIKeyStore {
  static let shared = APIKeyStore()

  private let service = "com.generalizable.anthropic"
  private let account = "anthropic_api_key"

  private var query: [CFString: Any] {
    [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
      kSecUseDataProtectionKeychain: true,
    ]
  }

  func read() -> String? {
    var q = query
    q[kSecReturnData] = true
    q[kSecMatchLimit] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
    let key = String(decoding: data, as: UTF8.self)
    return key.isEmpty ? nil : key
  }

  @discardableResult
  func write(_ key: String) -> Bool {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return delete() }
    let attrs: [CFString: Any] = [
      kSecValueData: Data(trimmed.utf8),
      kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    switch SecItemUpdate(query as CFDictionary, attrs as CFDictionary) {
    case errSecSuccess:
      return true
    case errSecItemNotFound:
      var add = query
      add.merge(attrs) { _, new in new }
      let status = SecItemAdd(add as CFDictionary, nil)
      if status == errSecDuplicateItem {
        return SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecSuccess
      }
      return status == errSecSuccess
    default:
      return false
    }
  }

  @discardableResult
  func delete() -> Bool {
    let status = SecItemDelete(query as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }
}
