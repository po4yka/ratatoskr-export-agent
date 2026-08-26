import CryptoKit
import Foundation
import Security

/// Stores one opaque credential set for each paired Platform device.
public final class KeychainDeviceCredentialStore: DeviceCredentialStoring, @unchecked Sendable {
  public static let defaultService = "com.po4yka.ratatoskr.export-agent.device-credentials"

  private let service: String

  public init(service: String = KeychainDeviceCredentialStore.defaultService) {
    self.service = service
  }

  public func save(_ credentials: DeviceCredentialSet, for identity: PairedDeviceIdentity) async throws {
    let data: Data
    do {
      data = try JSONEncoder().encode(credentials)
    } catch {
      throw DeviceCredentialError.unavailable
    }
    let updates: [CFString: Any] = [kSecValueData: data]
    let status = SecItemUpdate(query(for: identity) as CFDictionary, updates as CFDictionary)
    if status == errSecSuccess {
      return
    }
    guard status == errSecItemNotFound else {
      throw DeviceCredentialError.unavailable
    }
    var attributes = query(for: identity)
    attributes[kSecValueData] = data
    attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    attributes[kSecAttrSynchronizable] = kCFBooleanFalse!
    guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
      throw DeviceCredentialError.unavailable
    }
  }

  public func load(for identity: PairedDeviceIdentity) async throws -> DeviceCredentialSet? {
    var query = query(for: identity)
    query[kSecReturnData] = kCFBooleanTrue!
    query[kSecMatchLimit] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess, let data = result as? Data else {
      throw DeviceCredentialError.unavailable
    }
    do {
      return try JSONDecoder().decode(DeviceCredentialSet.self, from: data)
    } catch {
      throw DeviceCredentialError.unavailable
    }
  }

  public func remove(for identity: PairedDeviceIdentity) async throws {
    let status = SecItemDelete(query(for: identity) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw DeviceCredentialError.unavailable
    }
  }

  private func query(for identity: PairedDeviceIdentity) -> [CFString: Any] {
    [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account(for: identity),
      kSecAttrSynchronizable: kCFBooleanFalse!,
    ]
  }

  private func account(for identity: PairedDeviceIdentity) -> String {
    let source = "\(identity.origin.absoluteString)|\(identity.deviceID.uuidString)"
    return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
