import Foundation

extension NotesChannelClient {
  /// The most operations of one page of the queue.
  static let queuePageSize = 256

  /// Reads the queue of the connection (workspace spec `notes-write-delivery`)
  /// from its start, in pages of at most 256, applies each operation in order,
  /// and reports each result. Notes lists only the operations that wait for a
  /// result, so a pass that stopped reads the rest again on the next pass.
  ///
  /// While Obsidian does not run or its CLI does not answer, the pass ends
  /// with `awaitingObsidian` and the rest stays in the queue. A base mismatch
  /// gives the local file to `onLocalChange`, so the sync sends it.
  public func applyQueuedOperations(
    _ apply: ObsidianCLIApply, onLocalChange: @escaping @Sendable ([VaultChange]) -> Void = { _ in }
  ) async throws -> DeviceQueuePass {
    let pass = try await queuePass(apply, onLocalChange: onLocalChange)
    waitsForObsidian = pass == .awaitingObsidian
    return pass
  }

  private func queuePass(
    _ apply: ObsidianCLIApply, onLocalChange: @escaping @Sendable ([VaultChange]) -> Void
  ) async throws -> DeviceQueuePass {
    if case .stopped = status {
      return .answered(0)
    }
    guard connectionID != nil else {
      return .answered(0)
    }
    await loadKeptResults()
    var cursor: String?
    var answered = 0
    while true {
      let page = try await queuePage(after: cursor)
      // The CLI is asked once per pass, and only when an operation waits.
      if cursor == nil, !page.operations.isEmpty, !(await apply.isAvailable()) {
        return .awaitingObsidian
      }
      for operation in page.operations {
        guard let body = try await result(of: operation, apply, onLocalChange: onLocalChange) else {
          return .awaitingObsidian
        }
        try await report(body, of: operation)
        await keep(nil, for: operation.operationID)
        answered += 1
      }
      guard page.operations.count >= Self.queuePageSize else {
        // The queue lists no operation of a result that is still kept.
        await forgetKeptResults()
        return .answered(answered)
      }
      cursor = page.nextCursor
    }
  }

  private func queuePage(after cursor: String?) async throws -> DeviceOperationPage {
    let query = cursor.flatMap { $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) }.map { "?after=\($0)" } ?? ""
    let answer = try await get("device-operations\(query)")
    guard answer.status == 200 else {
      throw NotesFault.error(of: answer)
    }
    return try decodeNotesAnswer(DeviceOperationPage.self, from: answer)
  }

  func content(of operation: DeviceOperation) async throws -> Data {
    let answer = try await get("device-operations/\(operation.operationID)/content", bound: operation.contentLength)
    guard answer.status == 200 else {
      throw NotesFault.error(of: answer)
    }
    return answer.body
  }

  /// A `GET` on a route of the connection. With `bound`, the binding reads
  /// at most `bound` and one byte of the body.
  private func get(_ route: String, bound: Int? = nil) async throws -> NotesChannelAnswer {
    guard let connectionID else {
      throw NotesChannelError.connectionGone
    }
    return try await http.perform(
      NotesChannelRequest(method: "GET", path: "v1/notes/connections/\(connectionID)/\(route)", maximumBodyBytes: bound)
    )
  }

  /// The changes that send the local files of a base mismatch: the file of
  /// the operation, or each linking note that does not have its base hash.
  func localChanges(of outcome: DeviceOperationOutcome, _ operation: DeviceOperation) -> [VaultChange] {
    switch outcome {
    case .baseMismatch(let local):
      let kind: VaultChangeKind = local == nil ? .deleted : (operation.baseHash == nil ? .created : .updated)
      return [VaultChange(sequence: 0, kind: kind, path: operation.path)]
    case .rewriteMismatch(let local, let rewrites):
      let file = local == operation.baseHash ? [] : [VaultChange(sequence: 0, kind: local == nil ? .deleted : .updated, path: operation.path)]
      return file + rewrites.filter(\.differs).map { VaultChange(sequence: 0, kind: $0.sha256 == nil ? .deleted : .updated, path: $0.path) }
    default:
      return []
    }
  }

  /// Uploads the bytes of each linking note whose hash is not its expected
  /// hash, before the result names it: notes holds the expected bytes only.
  func uploadRewrites(of outcome: DeviceOperationOutcome, _ operation: DeviceOperation) async throws {
    guard case .applied(_, let rewrites) = outcome else {
      return
    }
    let expected = Dictionary(operation.rewrites.map { ($0.path, $0.expectedSHA256) }, uniquingKeysWith: { first, _ in first })
    let changed = rewrites.filter { $0.sha256 != nil && $0.sha256 != expected[$0.path] ?? nil }
    guard !changed.isEmpty else {
      return
    }
    try await upload(changed.compactMap(\.sha256), from: try changed.map(\.path).compactMap(blobFile))
  }

  /// The file at `path` with its hash and length; nil when it is gone.
  func blobFile(_ path: String) throws -> NotesBlobFile? {
    let url = vault.appendingPathComponent(path)
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }
    let found = try StreamingHasher().fingerprint(at: url)
    return NotesBlobFile(path: path, sha256: found.sha256Hex, lengthBytes: found.byteSize)
  }
}
