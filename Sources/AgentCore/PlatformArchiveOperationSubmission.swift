import Foundation

/// Provider routes supported by Platform's archive-operation boundary.
public enum PlatformArchiveProvider: String, Codable, Sendable {
  case chatgpt
  case claude
}

/// The bounded Platform acknowledgement that fixes where one archive may go.
public struct PlatformArchivePrepared: Equatable, Sendable {
  public let operationID: UUID

  public init(operationID: UUID) {
    self.operationID = operationID
  }
}

/// A second prepare would create a competing upload attempt; the existing operation must be
/// polled instead.
public enum OperationBoundArchiveSubmissionError: Error, Equatable, Sendable {
  case operationAlreadyBound
}

/// The two acknowledged boundaries of a Platform archive operation.
public protocol PlatformArchiveOperationTransport: Sendable {
  func prepare(
    provider: PlatformArchiveProvider,
    fingerprint: ArchiveFingerprint,
    idempotencyKey: String
  ) async throws -> PlatformArchivePrepared

  func openTransfer(
    provider: PlatformArchiveProvider, operationID: UUID,
    declaration: BlobUploadDeclaration, idempotencyKey: String
  ) async throws -> BlobUploadSession
  func transferStatus(
    provider: PlatformArchiveProvider, operationID: UUID, token: String
  ) async throws -> BlobUploadStatus
  func sendChunk(
    provider: PlatformArchiveProvider, operationID: UUID, token: String,
    index: Int, bytes: Data
  ) async throws
  func finalizeTransfer(
    provider: PlatformArchiveProvider, operationID: UUID, token: String
  ) async throws -> BlobStoredReceipt
}

/// Performs an operation-bound submission for an already preserved archive.
public struct OperationBoundArchiveSubmitter {
  private let journal: LocalArchiveJournal
  private let transport: any PlatformArchiveOperationTransport

  public init(
    journal: LocalArchiveJournal,
    transport: any PlatformArchiveOperationTransport
  ) {
    self.journal = journal
    self.transport = transport
  }

  /// Sends the managed copy after Platform accepts its archive operation.
  public func submit(entryID: UUID, provider: PlatformArchiveProvider) async throws {
    guard let entry = journal.entries.first(where: { $0.id == entryID }),
          let path = entry.managedArchivePath else {
      throw LocalJournalError.missingEntry
    }
    guard entry.operationID == nil else {
      throw OperationBoundArchiveSubmissionError.operationAlreadyBound
    }
    let prepared = try await transport.prepare(
      provider: provider, fingerprint: entry.fingerprint, idempotencyKey: entry.idempotencyKey
    )
    _ = try journal.bindBackendOperation(entryID: entryID, operationID: prepared.operationID)
    _ = try await ResumableArchiveUploader(chunkSize: 1_048_576).upload(
      archiveURL: URL(filePath: path), fingerprint: entry.fingerprint,
      mediaType: "application/zip", idempotencyKey: entry.idempotencyKey,
      transport: OperationReceiptTransport(
        provider: provider, operationID: prepared.operationID, transport: transport
      )
    )
  }
}

struct OperationReceiptTransport: BlobReceiptTransport {
  let provider: PlatformArchiveProvider
  let operationID: UUID
  let transport: any PlatformArchiveOperationTransport

  func open(
    _ declaration: BlobUploadDeclaration, idempotencyKey: String
  ) async throws -> BlobUploadSession {
    try await transport.openTransfer(
      provider: provider, operationID: operationID,
      declaration: declaration, idempotencyKey: idempotencyKey
    )
  }

  func status(token: String) async throws -> BlobUploadStatus {
    try await transport.transferStatus(provider: provider, operationID: operationID, token: token)
  }

  func send(token: String, index: Int, bytes: Data) async throws {
    try await transport.sendChunk(
      provider: provider, operationID: operationID, token: token, index: index, bytes: bytes
    )
  }

  func finalize(token: String) async throws -> BlobStoredReceipt {
    try await transport.finalizeTransfer(provider: provider, operationID: operationID, token: token)
  }
}
