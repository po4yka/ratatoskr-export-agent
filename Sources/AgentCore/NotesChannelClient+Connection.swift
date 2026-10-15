import Foundation

extension NotesChannelClient {
  /// Sends the manifest, and connects again once when the connection is gone.
  func reconcile() async throws {
    await restoreState()
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

  /// Whether the manifest of the connection is applied.
  public var isReady: Bool {
    ready
  }

  /// Forgets the connection, also the saved one, and ends a stop, so the
  /// next start connects again. For a vault whose connection the owner
  /// removed, when the owner wants it connected again.
  public func connectAgain() async {
    try? await stateStore?.remove(vaultKey: vaultKey)
    connectionID = nil
    stateRestored = true
    ready = false
    pending.removeAll()
    status = .notConnected
  }

  /// Before the first connect, takes the connection that a run before this
  /// one saved for the vault. The manifest then goes to it first.
  func restoreState() async {
    guard !stateRestored else {
      return
    }
    stateRestored = true
    guard connectionID == nil, let saved = try? await stateStore?.load(vaultKey: vaultKey) else {
      return
    }
    connectionID = saved.connectionID
    status = .connected(connectionID: saved.connectionID)
  }

  /// Saves the connection and its committed sequence. A failed save loses
  /// only the resume of the next start, so it does not stop a send.
  func saveState(committed: UInt64) async {
    guard let stateStore, let connectionID else {
      return
    }
    try? await stateStore.save(VaultChannelState(vaultKey: vaultKey, connectionID: connectionID, committedSequence: committed))
  }

  func connect() async throws {
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
    await saveState(committed: 0)
  }

  func sendManifest() async throws {
    let manifest = await manifest()
    guard manifest.entries.count <= NotesFault.maximumManifestEntries else {
      throw NotesChannelError.permanent(code: NotesFault.manifestTooLarge)
    }
    let body = try manifest.encoded()
    let files = manifest.entries.map { NotesBlobFile(path: $0.path, sha256: $0.sha256, lengthBytes: $0.lengthBytes) }
    for _ in 0..<3 {
      let answer = try await perform("POST", "manifest", body: body)
      guard answer.status != 413 else {
        throw NotesChannelError.permanent(code: NotesFault.manifestTooLarge)
      }
      guard answer.status == 200 else {
        throw NotesFault.error(of: answer)
      }
      let decoded = try decodeNotesAnswer(NotesManifestAnswer.self, from: answer)
      if decoded.neededSHA256.isEmpty {
        pending.removeAll()
        renumber(after: decoded.committedSequence)
        ready = true
        await saveState(committed: decoded.committedSequence)
        return
      }
      try await upload(decoded.neededSHA256, from: files)
    }
    throw NotesChannelError.notSettled
  }
}
