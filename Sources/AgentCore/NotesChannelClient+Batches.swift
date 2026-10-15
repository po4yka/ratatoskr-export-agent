import Foundation

/// A file whose bytes the notes service can ask for.
struct NotesBlobFile: Equatable, Sendable {
  let path: String
  let sha256: String
  let lengthBytes: Int
}

extension NotesChannelClient {
  /// Sends the waiting changes. When the connection is gone, or when a file
  /// changed after its change was recorded, only a manifest can describe the
  /// vault, so the client sends one.
  func flushOrReconcile() async throws {
    do {
      try await flush()
    } catch NotesChannelError.connectionGone {
      forgetConnection()
      try await reconcile()
    } catch NotesChannelError.staleBytes {
      ready = false
      try await reconcile()
    }
  }

  private func flush() async throws {
    var limit = VaultChangeBatch.maximumChanges
    var rounds = 0
    while !pending.isEmpty {
      rounds += 1
      guard rounds <= Self.maximumRounds else {
        throw NotesChannelError.notSettled
      }
      let batch = Array(pending.prefix(limit))
      let answer = try await perform("POST", "changes", body: try VaultChangeBatch(changes: batch).encoded())
      let fault = NotesFault.of(answer)
      switch (answer.status, fault?.code) {
      case (200, _):
        let committed = try decodeNotesAnswer(NotesBatchCommitted.self, from: answer).committedSequence
        pending.removeAll { $0.sequence <= committed }
        await saveState(committed: committed)
      case (409, NotesFault.sequenceGap):
        guard let committed = fault?.committedSequence else {
          throw NotesChannelError.invalidAnswer
        }
        pending.removeAll { $0.sequence <= committed }
        renumber(after: committed)
      case (409, NotesFault.bytesMissing):
        let files = batch.compactMap { change in
          change.sha256.map { NotesBlobFile(path: change.path, sha256: $0, lengthBytes: change.byteLength ?? 0) }
        }
        try await upload(fault?.missingSHA256 ?? [], from: files)
      case (413, _):
        limit = max(1, (batch.count + 1) / 2)
      default:
        throw NotesFault.error(of: answer)
      }
    }
  }

  /// Uploads the bytes of each hash from a file that has it, in 1 MiB
  /// chunks. The empty file needs no upload: notes refuses a 0-byte upload.
  func upload(_ hashes: [String], from files: [NotesBlobFile]) async throws {
    guard let connectionID else {
      throw NotesChannelError.connectionGone
    }
    let transport = NotesBlobTransport(http: http, connectionID: connectionID)
    for hash in Set(hashes).sorted() {
      guard let file = files.first(where: { $0.sha256 == hash }) else {
        throw NotesChannelError.staleBytes
      }
      guard file.lengthBytes > 0 else {
        continue
      }
      do {
        _ = try await ResumableArchiveUploader(chunkSize: Self.chunkSizeBytes).upload(
          archiveURL: vault.appendingPathComponent(file.path),
          fingerprint: ArchiveFingerprint(sha256Hex: hash, byteSize: file.lengthBytes),
          mediaType: "application/octet-stream",
          idempotencyKey: hash,
          transport: transport
        )
      } catch BlobReceiptTransportError.invalidReceipt, BlobReceiptTransportError.permanent, is CocoaError {
        throw NotesChannelError.staleBytes
      }
    }
  }

  /// One request on a route of the connection.
  func perform(_ method: String, _ route: String, body: Data) async throws -> NotesChannelAnswer {
    guard let connectionID else {
      throw NotesChannelError.connectionGone
    }
    return try await http.perform(
      NotesChannelRequest(
        method: method, path: "v1/notes/connections/\(connectionID)/\(route)", body: body, contentType: "application/json"
      )
    )
  }
}
