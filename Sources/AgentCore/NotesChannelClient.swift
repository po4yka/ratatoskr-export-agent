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
  /// The owner removed the connection (`410` `notes.connection.removed`).
  case connectionRemoved
  /// No file of the request has the bytes that the notes service asks for,
  /// or the file changed after its change was recorded.
  case staleBytes
  /// The answers did not settle within the bound of rounds.
  case notSettled
  case invalidAnswer
  case refused(status: Int, code: String?)
  /// A refusal that no retry can change; the code names the cause.
  case permanent(code: String)
}

/// The `cli` channel of one vault (workspace spec `notes-device-channels`).
///
/// The client connects, sends the manifest, and then sends the changes in
/// batches of at most 256. The committed sequence of the connection is the
/// authority: the client numbers each change after it. An applied manifest
/// describes the whole vault, so it replaces the changes that wait.
public actor NotesChannelClient {
  public internal(set) var status: NotesChannelStatus = .notConnected
  /// The upload chunk size that the client declares (1 MiB).
  public static let chunkSizeBytes = 1_048_576
  static let maximumRounds = 64

  let http: any NotesChannelHTTP
  let vault: URL
  let vaultKey: String
  let vaultDisplayName: String
  let manifest: @Sendable () async -> VaultManifest
  let stateStore: (any VaultChannelStateStoring)?
  var connectionID: String?
  var stateRestored = false
  var ready = false
  var pending: [VaultChange] = []
  private var nextSequence: UInt64 = 1

  public init(
    http: any NotesChannelHTTP,
    vault: URL,
    vaultKey: String,
    vaultDisplayName: String,
    connectionID: String? = nil,
    stateStore: (any VaultChannelStateStoring)? = nil,
    manifest: @escaping @Sendable () async -> VaultManifest
  ) {
    self.http = http
    self.vault = vault
    self.vaultKey = vaultKey
    self.vaultDisplayName = vaultDisplayName
    self.connectionID = connectionID
    self.stateStore = stateStore
    self.manifest = manifest
    if let connectionID {
      status = .connected(connectionID: connectionID)
    }
  }

  /// Connects when there is no connection, then sends the manifest.
  public func start() async throws {
    try checkNotStopped()
    do {
      try await reconcile()
    } catch {
      throw stopOnRefusal(error)
    }
  }

  /// Numbers the changes after the committed sequence and sends them. Before
  /// the first applied manifest, the client starts first.
  public func send(_ changes: [VaultChange]) async throws {
    try checkNotStopped()
    for change in changes {
      var numbered = change
      numbered.sequence = nextSequence
      nextSequence += 1
      pending.append(numbered)
    }
    do {
      if !ready {
        try await reconcile()
      }
      try await flushOrReconcile()
    } catch {
      throw stopOnRefusal(error)
    }
  }

  /// Sends the manifest of the vault now. It replaces the changes that
  /// wait, for example after the buffer of a sync dropped changes.
  public func resync() async throws {
    try checkNotStopped()
    ready = false
    do {
      try await reconcile()
    } catch {
      throw stopOnRefusal(error)
    }
  }

  func forgetConnection() {
    connectionID = nil
    ready = false
    status = .notConnected
  }

  /// Gives the waiting changes the sequences after `committed`.
  func renumber(after committed: UInt64) {
    for index in pending.indices {
      pending[index].sequence = committed + 1 + UInt64(index)
    }
    nextSequence = committed + 1 + UInt64(pending.count)
  }

  private func checkNotStopped() throws {
    if case .stopped(let code) = status {
      switch code {
      case NotesFault.removed: throw NotesChannelError.connectionRemoved
      case NotesFault.channelMismatch: throw NotesChannelError.channelMismatch
      default: throw NotesChannelError.permanent(code: code)
      }
    }
  }

  /// A refusal that no retry can change stops the channel: another device or
  /// channel owns the vault, the owner removed the connection, or an answer
  /// is `permanent` (the code names the cause).
  private func stopOnRefusal(_ error: any Error) -> any Error {
    let code: String
    switch error {
    case NotesChannelError.channelMismatch: code = NotesFault.channelMismatch
    case NotesChannelError.connectionRemoved: code = NotesFault.removed
    case NotesChannelError.permanent(let cause): code = cause
    default: return error
    }
    status = .stopped(code: code)
    pending.removeAll()
    ready = false
    return error
  }
}
