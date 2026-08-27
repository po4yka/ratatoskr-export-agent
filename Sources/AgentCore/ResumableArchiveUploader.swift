import Foundation

public struct UploadProgress: Equatable, Sendable {
  public let completedBytes: Int
  public let totalBytes: Int

  public init(completedBytes: Int, totalBytes: Int) {
    self.completedBytes = completedBytes
    self.totalBytes = totalBytes
  }
}

/// Streams one receipt-protocol chunk at a time. Durable state is reported at
/// every receiver acknowledgement; callers decide where that state is stored.
public struct ResumableArchiveUploader: Sendable {
  public let chunkSize: Int

  public init(chunkSize: Int) {
    self.chunkSize = chunkSize
  }

  @discardableResult
  public func upload(
    archiveURL: URL,
    fingerprint: ArchiveFingerprint,
    mediaType: String,
    idempotencyKey: String,
    checkpoint: BlobUploadSession? = nil,
    transport: any BlobReceiptTransport,
    didOpenSession: @Sendable (BlobUploadSession) async throws -> Void = { _ in },
    didAcknowledge: @Sendable (BlobUploadSession, Set<Int>) async throws -> Void = { _, _ in },
    admitChunk: @Sendable (Int) async -> Bool = { _ in true },
    didProgress: @Sendable (UploadProgress) -> Void = { _ in }
  ) async throws -> BlobStoredReceipt {
    let session = try await openOrResume(
      fingerprint: fingerprint, mediaType: mediaType, idempotencyKey: idempotencyKey,
      checkpoint: checkpoint, transport: transport, didOpenSession: didOpenSession
    )
    let acknowledged = try await receivedIndices(
      for: session, fingerprint: fingerprint, transport: transport, didAcknowledge: didAcknowledge
    )
    try await streamMissingChunks(
      from: archiveURL, fingerprint: fingerprint, session: session, acknowledged: acknowledged,
      transport: transport, didAcknowledge: didAcknowledge, admitChunk: admitChunk, didProgress: didProgress
    )
    let receipt = try await transport.finalize(token: session.token)
    try BlobReceiptVerification.verify(receipt, fingerprint: fingerprint)
    return receipt
  }

  private func openOrResume(
    fingerprint: ArchiveFingerprint, mediaType: String, idempotencyKey: String,
    checkpoint: BlobUploadSession?, transport: any BlobReceiptTransport,
    didOpenSession: @Sendable (BlobUploadSession) async throws -> Void
  ) async throws -> BlobUploadSession {
    if let checkpoint {
      return checkpoint
    }
    let session = try await transport.open(
      BlobUploadDeclaration(fingerprint: fingerprint, mediaType: mediaType, chunkSizeBytes: chunkSize),
      idempotencyKey: idempotencyKey
    )
    try await didOpenSession(session)
    return session
  }

  private func receivedIndices(
    for session: BlobUploadSession, fingerprint: ArchiveFingerprint,
    transport: any BlobReceiptTransport,
    didAcknowledge: @Sendable (BlobUploadSession, Set<Int>) async throws -> Void
  ) async throws -> Set<Int> {
    let received = try await transport.status(token: session.token).receivedIndices
    let count = max(1, (fingerprint.byteSize + session.chunkSizeBytes - 1) / session.chunkSizeBytes)
    guard received.allSatisfy({ $0 >= 0 && $0 < count }) else {
      throw BlobReceiptTransportError.permanent
    }
    try await didAcknowledge(session, received)
    return received
  }

  private func streamMissingChunks(
    from archiveURL: URL, fingerprint: ArchiveFingerprint, session: BlobUploadSession,
    acknowledged originalAcknowledged: Set<Int>, transport: any BlobReceiptTransport,
    didAcknowledge: @Sendable (BlobUploadSession, Set<Int>) async throws -> Void,
    admitChunk: @Sendable (Int) async -> Bool, didProgress: @Sendable (UploadProgress) -> Void
  ) async throws {
    let handle = try FileHandle(forReadingFrom: archiveURL)
    defer { try? handle.close() }
    let count = max(1, (fingerprint.byteSize + session.chunkSizeBytes - 1) / session.chunkSizeBytes)
    var acknowledged = originalAcknowledged
    var completed = 0
    for index in 0 ..< count {
      let expected = min(session.chunkSizeBytes, fingerprint.byteSize - index * session.chunkSizeBytes)
      if acknowledged.contains(index) {
        completed += expected; continue
      }
      guard await admitChunk(expected) else { throw BlobReceiptTransportError.capacityUnavailable }
      let bytes = try handle.read(upToCount: expected) ?? Data()
      guard bytes.count == expected else { throw BlobReceiptTransportError.permanent }
      try await transport.send(token: session.token, index: index, bytes: bytes)
      acknowledged.insert(index)
      completed += expected
      try await didAcknowledge(session, acknowledged)
      didProgress(.init(completedBytes: completed, totalBytes: fingerprint.byteSize))
    }
  }
}
