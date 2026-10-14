import Foundation

/// The body of `POST /v1/notes/connections/{id}/changes`, the same batch
/// format as the plugin channel (workspace spec `notes-device-channels`).
public struct VaultChangeBatch: Codable, Equatable, Sendable {
  /// The largest batch that `ratatoskr-notes` accepts.
  public static let maximumChanges = 256

  public var changes: [VaultChange]

  public init(changes: [VaultChange]) {
    precondition(changes.count <= Self.maximumChanges, "a change batch holds at most 256 changes")
    self.changes = changes
  }

  /// Splits changes, in sequence order, into batches of at most 256.
  public static func batches(of changes: [VaultChange]) -> [VaultChangeBatch] {
    stride(from: 0, to: changes.count, by: maximumChanges).map { start in
      VaultChangeBatch(changes: Array(changes[start..<min(start + maximumChanges, changes.count)]))
    }
  }

  /// The JSON body. Keys are sorted so that equal batches give equal bytes.
  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }
}
