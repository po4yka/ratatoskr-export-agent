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
    "Vault \(row.displayName): \(state(row.status))"
  }

  /// Only a connection that the owner removed can be connected again; a
  /// vault that another device or channel sends stays stopped.
  public static func canConnectAgain(_ row: VaultStatusRow) -> Bool {
    row.status == .stopped(code: NotesFault.removed)
  }

  private static func state(_ status: VaultSyncStatus) -> String {
    switch status {
    case .connecting: "connecting"
    case .connected: "connected"
    case .retrying: "offline, trying again"
    case .stopped(NotesFault.removed): "stopped, the connection was removed"
    case .stopped(NotesFault.channelMismatch): "stopped, another device or channel sends this vault"
    case .stopped: "stopped"
    }
  }
}
