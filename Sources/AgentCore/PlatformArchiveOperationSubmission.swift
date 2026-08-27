import Foundation

/// Provider routes supported by Platform's archive-operation boundary.
public enum PlatformArchiveProvider: String, Codable, Sendable {
  case chatgpt
  case claude
}

/// The bounded Platform acknowledgement that fixes where one archive may go.
public struct PlatformArchivePrepared: Equatable, Sendable {
  public let operationID: UUID
  public let uploadPath: String

  public init(operationID: UUID, uploadPath: String) {
    self.operationID = operationID
    self.uploadPath = uploadPath
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

  func transfer(
    provider: PlatformArchiveProvider,
    prepared: PlatformArchivePrepared,
    archiveURL: URL,
    fingerprint: ArchiveFingerprint
  ) async throws
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
    guard entry.backendImport == nil else {
      throw OperationBoundArchiveSubmissionError.operationAlreadyBound
    }
    let prepared = try await transport.prepare(
      provider: provider, fingerprint: entry.fingerprint, idempotencyKey: entry.idempotencyKey
    )
    _ = try journal.bindBackendOperation(entryID: entryID, operationID: prepared.operationID)
    try await transport.transfer(
      provider: provider, prepared: prepared, archiveURL: URL(filePath: path),
      fingerprint: entry.fingerprint
    )
  }
}
