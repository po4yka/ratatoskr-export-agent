import Foundation

/// One file of a manifest on `/v1/notes/connections/{id}/manifest`.
public struct VaultManifestEntry: Codable, Equatable, Sendable {
  public var path: String
  public var sha256: String
  public var lengthBytes: Int

  public init(path: String, sha256: String, lengthBytes: Int) {
    self.path = path
    self.sha256 = sha256
    self.lengthBytes = lengthBytes
  }

  enum CodingKeys: String, CodingKey {
    case path
    case sha256
    case lengthBytes = "length_bytes"
  }
}

/// The body of `POST /v1/notes/connections/{id}/manifest`: every indexed file
/// of the vault (workspace spec `notes-device-channels`).
public struct VaultManifest: Codable, Equatable, Sendable {
  public var entries: [VaultManifestEntry]

  /// Makes the manifest from the index of a vault scan.
  public init(index: [String: ArchiveFingerprint]) {
    entries = index.sorted { $0.key < $1.key }.map { path, fingerprint in
      VaultManifestEntry(path: path, sha256: fingerprint.sha256Hex, lengthBytes: fingerprint.byteSize)
    }
  }

  /// The JSON body. Keys are sorted so that equal manifests give equal bytes.
  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }
}
