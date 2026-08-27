import Foundation

extension UploadQueue {
  @discardableResult
  public func runEligible(now: Date = Date()) async -> UploadQueueStatus {
    await limiter.beginTick()
    let entryIDs = journal.entries.filter { isEligible($0, at: now) }.map(\.id)
    await withTaskGroup(of: Void.self) { group in
      for entryID in entryIDs {
        group.addTask { await self.process(entryID: entryID, now: now) }
      }
    }
    let status = UploadQueueStatus(entries: journal.entries, now: now)
    publish(status)
    return status
  }

  func process(entryID: UUID, now: Date) async {
    guard await limiter.acquireUploadSlot() else { return }
    do {
      try await transfer(entryID: entryID, now: now)
    } catch {
      await recordFailure(entryID: entryID, error: error, now: now)
    }
    await limiter.releaseUploadSlot()
  }

  func transfer(entryID: UUID, now: Date) async throws {
    guard let queued = journal.entries.first(where: { $0.id == entryID }), isEligible(queued, at: now), let path = queued.managedArchivePath else { return }
    _ = try journal.advance(entryID: entryID, to: .uploading)
    publishStatus()
    if let operationTransport, let operationProvider {
      try await transferOperation(
        entryID: entryID, queued: queued, archiveURL: URL(filePath: path),
        provider: operationProvider, transport: operationTransport
      )
      return
    }
    guard let blobTransport else { throw PlatformDeviceTransportError.invalidResponse }
    let session = queued.uploadCheckpoint.flatMap { checkpoint in
      checkpoint.resumptionToken.map {
        BlobUploadSession(token: $0, chunkSizeBytes: checkpoint.chunkSizeBytes)
      }
    }

    _ = try await ResumableArchiveUploader(chunkSize: chunkSize).upload(
      archiveURL: URL(filePath: path),
      fingerprint: queued.fingerprint,
      mediaType: "application/zip",
      idempotencyKey: queued.idempotencyKey,
      checkpoint: session,
      transport: blobTransport,
      didOpenSession: { session in
        try await self.persistAcknowledgement(entryID: entryID, session: session, indices: [])
      },
      didAcknowledge: { session, indices in
        try await self.persistAcknowledgement(entryID: entryID, session: session, indices: indices)
      },
      admitChunk: { bytes in
        await self.limiter.reserveBytes(bytes: bytes)
      }
    )
    _ = try journal.advance(entryID: entryID, to: .uploaded)
    publishStatus()
  }

  func transferOperation(
    entryID: UUID,
    queued: JournalEntry,
    archiveURL: URL,
    provider: PlatformArchiveProvider,
    transport: any PlatformArchiveOperationTransport
  ) async throws {
    let prepared = try await transport.prepare(
      provider: provider, fingerprint: queued.fingerprint, idempotencyKey: queued.idempotencyKey
    )
    _ = try journal.bindBackendOperation(entryID: entryID, operationID: prepared.operationID)
    try await transport.transfer(
      provider: provider, prepared: prepared, archiveURL: archiveURL, fingerprint: queued.fingerprint
    )
    _ = try journal.advance(entryID: entryID, to: .uploaded)
    publishStatus()
  }

  func persistAcknowledgement(
    entryID: UUID,
    session: BlobUploadSession,
    indices: Set<Int>
  ) throws {
    guard let previous = journal.entries.first(where: { $0.id == entryID }) else {
      throw LocalJournalError.missingEntry
    }
    let checkpoint = previous.uploadCheckpoint
    _ = try journal.checkpoint(
      entryID: entryID,
      upload: UploadCheckpoint(
        resumptionToken: session.token,
        chunkSizeBytes: session.chunkSizeBytes,
        acknowledgedIndices: indices,
        attemptCount: checkpoint?.attemptCount ?? 0,
        nextRetryAt: checkpoint?.nextRetryAt,
        control: checkpoint?.control ?? .active
      )
    )
    publishStatus()
  }
}
