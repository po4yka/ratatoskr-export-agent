import Foundation

/// What the menu shows for the `cli` channel of one vault.
public enum VaultSyncStatus: Equatable, Sendable {
  case connecting
  case connected
  /// A send or a start failed; the sync tries again after the backoff.
  case retrying
  /// The notes service refused the vault with this code; nothing is sent.
  case stopped(code: String)
}

/// One vault in the menu.
public struct VaultStatusRow: Equatable, Sendable {
  public let id: UUID
  public let displayName: String
  public let status: VaultSyncStatus

  public init(id: UUID, displayName: String, status: VaultSyncStatus) {
    self.id = id
    self.displayName = displayName
    self.status = status
  }
}

/// Renders the status of a vault into a menu row.
public enum VaultStatusMenuProjection {
  public static func title(_ row: VaultStatusRow) -> String {
    ""
  }

  /// Only the owner removed a connection that the agent can connect again.
  public static func canConnectAgain(_ row: VaultStatusRow) -> Bool {
    false
  }
}
