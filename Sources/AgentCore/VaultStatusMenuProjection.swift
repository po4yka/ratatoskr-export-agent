import Foundation

/// What the menu shows for the `cli` channel of one vault.
public enum VaultSyncStatus: Equatable, Sendable {
  case connecting
  case connected
  /// A send or a start failed; the sync tries again after the backoff.
  case retrying
  /// The notes service refused the vault with this code; nothing is sent.
  case stopped(code: String)
  /// Writes wait in the queue of the connection while the Obsidian app does
  /// not run.
  case awaitingObsidian
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

  /// A connection that the owner removed, or a vault that already has
  /// another connection (after the owner removes it), can be connected
  /// again; a vault that another device or channel sends stays stopped.
  public static func canConnectAgain(_ row: VaultStatusRow) -> Bool {
    row.status == .stopped(code: NotesFault.removed) || row.status == .stopped(code: NotesFault.vaultAlreadyConnected)
  }

  private static func state(_ status: VaultSyncStatus) -> String {
    switch status {
    case .connecting: "connecting"
    case .connected: "connected"
    case .awaitingObsidian: "waits for Obsidian"
    case .retrying: "offline, trying again"
    case .stopped(NotesFault.removed): "stopped, the connection was removed"
    case .stopped(NotesFault.channelMismatch): "stopped, another device or channel sends this vault"
    case .stopped(NotesFault.vaultAlreadyConnected): "stopped, the vault already has another connection"
    case .stopped(NotesFault.invalidRequest): "stopped, notes refused a request of this agent"
    case .stopped(NotesFault.manifestTooLarge): "stopped, the vault has more than 100 000 files"
    case .stopped: "stopped"
    }
  }
}
