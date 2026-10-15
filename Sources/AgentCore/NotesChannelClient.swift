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
}

/// The `cli` channel of one vault (workspace spec `notes-device-channels`).
///
/// The client connects, sends the manifest, and then sends the changes in
/// batches of at most 256. The committed sequence of the connection is the
/// authority: the client numbers each change after it. An applied manifest
/// describes the whole vault, so it replaces the changes that wait.
public actor NotesChannelClient {
  public private(set) var status: NotesChannelStatus = .notConnected
  /// The upload chunk size that the client declares (1 MiB).
  public static let chunkSizeBytes = 1_048_576
  static let maximumRounds = 64

  let http: any NotesChannelHTTP
  let vault: URL
  private let vaultKey: String
  private let vaultDisplayName: String
  private let manifest: @Sendable () async -> VaultManifest
  var connectionID: String?
  var ready = false
  var pending: [VaultChange] = []
  private var nextSequence: UInt64 = 1

  public init(
    http: any NotesChannelHTTP,
    vault: URL,
    vaultKey: String,
    vaultDisplayName: String,
    connectionID: String? = nil,
    manifest: @escaping @Sendable () async -> VaultManifest
  ) {
    self.http = http
    self.vault = vault
    self.vaultKey = vaultKey
    self.vaultDisplayName = vaultDisplayName
    self.connectionID = connectionID
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
      throw stopOnMismatch(error)
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
      throw stopOnMismatch(error)
    }
  }

  /// Sends the manifest, and connects again once when the connection is gone.
  func reconcile() async throws {
    for attempt in 0..<2 {
      do {
        if connectionID == nil {
          try await connect()
        }
        try await sendManifest()
        return
      } catch NotesChannelError.connectionGone where attempt == 0 {
        forgetConnection()
      }
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

  private func connect() async throws {
    let body = try JSONEncoder().encode(NotesConnectBody(vaultKey: vaultKey, vaultDisplayName: vaultDisplayName))
    let answer = try await http.perform(
      NotesChannelRequest(method: "POST", path: "v1/notes/connections", body: body, contentType: "application/json")
    )
    guard answer.status == 202 else {
      throw NotesFault.error(of: answer)
    }
    let id = try decodeNotesAnswer(NotesConnectAccepted.self, from: answer).connection.connectionID
    connectionID = id
    status = .connected(connectionID: id)
  }

  private func sendManifest() async throws {
    let manifest = await manifest()
    let body = try manifest.encoded()
    let files = manifest.entries.map { NotesBlobFile(path: $0.path, sha256: $0.sha256, lengthBytes: $0.lengthBytes) }
    for _ in 0..<3 {
      let answer = try await perform("POST", "manifest", body: body)
      guard answer.status == 200 else {
        throw NotesFault.error(of: answer)
      }
      let decoded = try decodeNotesAnswer(NotesManifestAnswer.self, from: answer)
      if decoded.neededSHA256.isEmpty {
        pending.removeAll()
        renumber(after: decoded.committedSequence)
        ready = true
        return
      }
      try await upload(decoded.neededSHA256, from: files)
    }
    throw NotesChannelError.notSettled
  }

  private func checkNotStopped() throws {
    if case .stopped = status {
      throw NotesChannelError.channelMismatch
    }
  }

  private func stopOnMismatch(_ error: any Error) -> any Error {
    if case NotesChannelError.channelMismatch = error {
      status = .stopped(code: NotesFault.channelMismatch)
      pending.removeAll()
      ready = false
    }
    return error
  }
}
