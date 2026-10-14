import Foundation

/// What the `cli` channel of one vault can do now.
public enum NotesChannelStatus: Equatable, Sendable {
  case notConnected
  case connected(connectionID: String)
  /// The notes service refused the device with this code; nothing is sent.
  case stopped(code: String)
}

public enum NotesChannelError: Error, Equatable, Sendable {
  /// Another device or channel owns the vault (`notes.channel_mismatch`).
  case channelMismatch
  /// The connection does not exist (`notes.connection.not_found`).
  case connectionGone
  /// No file of the request has the bytes that the notes service asks for.
  case staleBytes
  /// The answers did not settle within the bound of rounds.
  case notSettled
  case invalidAnswer
  case refused(status: Int, code: String?)
}

/// The `cli` channel of one vault (workspace spec `notes-device-channels`).
public actor NotesChannelClient {
  public private(set) var status: NotesChannelStatus = .notConnected

  public init(
    http: any NotesChannelHTTP,
    vault: URL,
    vaultKey: String,
    vaultDisplayName: String,
    connectionID: String? = nil,
    manifest: @escaping @Sendable () async -> VaultManifest
  ) {}

  /// Connects when there is no connection, then sends the manifest.
  public func start() async throws {}

  /// Sends the changes after the committed sequence.
  public func send(_ changes: [VaultChange]) async throws {}
}
