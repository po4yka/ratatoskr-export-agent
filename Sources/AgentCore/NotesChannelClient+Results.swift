import Foundation

/// The results of the queue: each result is kept, also in the result store,
/// until notes takes it, so a pass after an error or a restart sends it again
/// in place of a new apply.
extension NotesChannelClient {
  /// Takes the results that a run before this one kept for the connection.
  func loadKeptResults() async {
    guard !resultsLoaded, let connectionID else {
      return
    }
    resultsLoaded = true
    if let saved = try? await resultStore?.load(connectionID: connectionID) {
      unsentResults.merge(saved) { kept, _ in kept }
    }
  }

  /// Keeps `body` for the operation, or forgets it when nil, and saves.
  func keep(_ body: Data?, for operationID: String) async {
    guard unsentResults[operationID] != body else {
      return
    }
    unsentResults[operationID] = body
    await saveKeptResults()
  }

  /// Forgets every kept result: the queue lists none of their operations.
  func forgetKeptResults() async {
    guard !unsentResults.isEmpty else {
      return
    }
    unsentResults.removeAll()
    await saveKeptResults()
  }

  /// A failed save loses only the resend after a restart, so it does not
  /// stop a pass.
  private func saveKeptResults() async {
    guard let resultStore, let connectionID else {
      return
    }
    try? await resultStore.save(unsentResults, connectionID: connectionID)
  }

  /// The result of `operation`: the result that notes did not take on an
  /// earlier pass, or the result of a new apply, kept until notes takes it.
  /// Nil when the operation waits for Obsidian.
  func result(
    of operation: DeviceOperation, _ apply: ObsidianCLIApply, onLocalChange: @Sendable ([VaultChange]) -> Void
  ) async throws -> Data? {
    if let kept = unsentResults[operation.operationID] {
      return kept
    }
    let outcome = try await apply.apply(operation) { try await self.content(of: operation) }
    guard let result = DeviceOperationResult(outcome) else {
      return nil
    }
    let body = try JSONEncoder().encode(result)
    await keep(body, for: operation.operationID)
    let changes = localChanges(of: outcome, operation)
    if !changes.isEmpty {
      onLocalChange(changes)
    }
    try await uploadRewrites(of: outcome, operation)
    return body
  }

  /// Sends the result. An `applied` result names bytes that notes must have:
  /// on `409` `notes.channel.bytes_missing` the client uploads the file of the
  /// result and sends the result again. A `404`
  /// `notes.device_operation.not_found` means that the operation ended. A
  /// `4xx` other than `409`, or bytes that changed before their upload, can
  /// never let notes take the kept result: it is dropped, and the next pass
  /// applies again.
  func report(_ body: Data, of operation: DeviceOperation) async throws {
    // Notes names one missing hash per answer: the file and each linking note.
    for _ in 0..<(2 + operation.rewrites.count) {
      let answer = try await perform("POST", "device-operations/\(operation.operationID)/result", body: body)
      let fault = NotesFault.of(answer)
      switch (answer.status, fault?.code) {
      case (200, _), (404, NotesFault.operationNotFound):
        return
      case (409, NotesFault.bytesMissing):
        let paths = [operation.resultPath] + operation.rewrites.map(\.path)
        do {
          try await upload(fault?.missingSHA256 ?? [], from: try paths.compactMap(blobFile))
        } catch NotesChannelError.staleBytes {
          await keep(nil, for: operation.operationID)
          throw NotesChannelError.staleBytes
        }
      default:
        if (400..<500).contains(answer.status), answer.status != 409 {
          await keep(nil, for: operation.operationID)
        }
        throw NotesFault.error(of: answer)
      }
    }
    throw NotesChannelError.notSettled
  }
}
