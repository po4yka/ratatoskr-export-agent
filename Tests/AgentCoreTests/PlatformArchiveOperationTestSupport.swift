import AgentCore
import CryptoKit
import Foundation

func write(_ data: Data) throws -> URL {
  let url = FileManager.default.temporaryDirectory.appending(path: "archive-\(UUID())")
  try data.write(to: url)
  return url
}

func digest(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func operationEntry(named: String) throws -> (LocalArchiveJournal, JournalEntry) {
  let bytes = Data("archive".utf8)
  let archiveURL = FileManager.default.temporaryDirectory.appending(path: "\(named)-\(UUID())")
  try bytes.write(to: archiveURL)
  let journal = try LocalArchiveJournal.open(
    at: FileManager.default.temporaryDirectory.appending(path: "\(named)-journal-\(UUID())")
  )
  let sha256 = digest(bytes)
  var entry = try journal.discover(
    fingerprint: ArchiveFingerprint(sha256Hex: sha256, byteSize: bytes.count),
    routing: fixtureRouting(provider: .claude),
    managedArchiveURL: archiveURL
  )
  for state in [JournalState.archived, .hashed, .queued] {
    entry = try journal.advance(entryID: entry.id, to: state)
  }
  return (journal, entry)
}

final class FailingTransferTransport: @unchecked Sendable, PlatformArchiveOperationTransport {
  let operationID: UUID

  init(operationID: UUID) { self.operationID = operationID }

  func prepare(provider _: PlatformArchiveProvider, fingerprint _: ArchiveFingerprint, idempotencyKey _: String) async throws -> PlatformArchivePrepared {
    PlatformArchivePrepared(operationID: operationID)
  }

  func openTransfer(
    provider _: PlatformArchiveProvider, operationID _: UUID,
    declaration _: BlobUploadDeclaration, idempotencyKey _: String
  ) async throws -> BlobUploadSession {
    throw PlatformDeviceTransportError.unavailable
  }

  func transferStatus(
    provider _: PlatformArchiveProvider, operationID _: UUID, token _: String
  ) async throws -> BlobUploadStatus { throw PlatformDeviceTransportError.unavailable }
  func sendChunk(
    provider _: PlatformArchiveProvider, operationID _: UUID,
    token _: String, index _: Int, bytes _: Data
  ) async throws { throw PlatformDeviceTransportError.unavailable }
  func finalizeTransfer(
    provider _: PlatformArchiveProvider, operationID _: UUID, token _: String
  ) async throws -> BlobStoredReceipt { throw PlatformDeviceTransportError.unavailable }
}
