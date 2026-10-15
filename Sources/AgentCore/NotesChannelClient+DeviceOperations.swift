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
    var cursor: String?
    var answered = 0
    while true {
      let page = try await queuePage(after: cursor)
      // The CLI is asked once per pass, and only when an operation waits.
      if cursor == nil, !page.operations.isEmpty, !(await apply.isAvailable()) {
        return .awaitingObsidian
      }
      for operation in page.operations {
        let outcome = try await apply.apply(operation) { try await self.content(of: operation) }
        guard let result = DeviceOperationResult(outcome) else {
          return .awaitingObsidian
        }
        if case .baseMismatch(let local) = outcome {
          onLocalChange([Self.localChange(operation, localSHA256: local)])
        }
        try await report(result, of: operation)
        answered += 1
      }
      guard page.operations.count >= Self.queuePageSize else {
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

  private func content(of operation: DeviceOperation) async throws -> Data {
    let answer = try await get("device-operations/\(operation.operationID)/content")
    guard answer.status == 200 else {
      throw NotesFault.error(of: answer)
    }
    return answer.body
  }

  /// Sends the result. An `applied` result names bytes that notes must have:
  /// on `409` `notes.channel.bytes_missing` the client uploads the file of the
  /// result and sends the result again. A `404`
  /// `notes.device_operation.not_found` means that the operation ended.
  private func report(_ result: DeviceOperationResult, of operation: DeviceOperation) async throws {
    let body = try JSONEncoder().encode(result)
    for _ in 0..<2 {
      let answer = try await perform("POST", "device-operations/\(operation.operationID)/result", body: body)
      let fault = NotesFault.of(answer)
      switch (answer.status, fault?.code) {
      case (200, _), (404, NotesFault.operationNotFound):
        return
      case (409, NotesFault.bytesMissing):
        let file = try StreamingHasher().fingerprint(at: vault.appendingPathComponent(operation.resultPath))
        try await upload(
          fault?.missingSHA256 ?? [],
          from: [NotesBlobFile(path: operation.resultPath, sha256: file.sha256Hex, lengthBytes: file.byteSize)]
        )
      default:
        throw NotesFault.error(of: answer)
      }
    }
    throw NotesChannelError.notSettled
  }

  private func get(_ route: String) async throws -> NotesChannelAnswer {
    guard let connectionID else {
      throw NotesChannelError.connectionGone
    }
    return try await http.perform(NotesChannelRequest(method: "GET", path: "v1/notes/connections/\(connectionID)/\(route)"))
  }

  /// The change that sends the local file of a base mismatch.
  private static func localChange(_ operation: DeviceOperation, localSHA256: String?) -> VaultChange {
    let kind: VaultChangeKind = localSHA256 == nil ? .deleted : (operation.baseHash == nil ? .created : .updated)
    return VaultChange(sequence: 0, kind: kind, path: operation.path)
  }
}
