import Foundation

/// What happened to one file of a connected vault. The same four kinds as the
/// plugin channel and `evt.notes.file.changed.v1`.
public enum VaultChangeKind: String, Codable, Equatable, Sendable {
  case created
  case updated
  case renamed
  case deleted
}

/// One entry of a change batch on `/v1/notes/connections/{id}/changes`.
///
/// The path is NFC and relative to the vault root. `previousPath` is set only
/// for `renamed`. `sha256` and `byteLength` (`length_bytes` on the wire)
/// describe the new bytes and are absent only for `deleted`. `sequence` is the
/// device change sequence, which increases by one per change.
public struct VaultChange: Codable, Equatable, Sendable {
  public var sequence: UInt64
  public var kind: VaultChangeKind
  public var path: String
  public var previousPath: String?
  public var sha256: String?
  public var byteLength: Int?

  public init(
    sequence: UInt64,
    kind: VaultChangeKind,
    path: String,
    previousPath: String? = nil,
    sha256: String? = nil,
    byteLength: Int? = nil
  ) {
    self.sequence = sequence
    self.kind = kind
    self.path = path
    self.previousPath = previousPath
    self.sha256 = sha256
    self.byteLength = byteLength
  }

  enum CodingKeys: String, CodingKey {
    case sequence
    case kind
    case path
    case previousPath = "previous_path"
    case sha256
    case byteLength = "length_bytes"
  }
}
