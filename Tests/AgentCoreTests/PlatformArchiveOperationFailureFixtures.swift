import AgentCore
import Foundation
import XCTest

struct OperationFixtureAuthorizer: PlatformRequestAuthorizing {
  func credentialForRequest() async throws -> String { "fixture" }
  func recoverCredential(afterRejectedCredential _: String) async throws -> String { "recovered" }
  func authorizationWasRejected(_: String) async {}
}

struct MalformedPrepareTransport: PlatformArchiveOperationTransport {
  func prepare(
    provider _: PlatformArchiveProvider, fingerprint _: ArchiveFingerprint,
    idempotencyKey _: String
  ) async throws -> PlatformArchivePrepared { throw PlatformDeviceTransportError.invalidResponse }
  func openTransfer(
    provider _: PlatformArchiveProvider, operationID _: UUID,
    declaration _: BlobUploadDeclaration, idempotencyKey _: String
  ) async throws -> BlobUploadSession { throw PlatformDeviceTransportError.unavailable }
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

final class CountingPrepareTransport: @unchecked Sendable, PlatformArchiveOperationTransport {
  private(set) var prepareCount = 0
  func prepare(
    provider _: PlatformArchiveProvider, fingerprint _: ArchiveFingerprint,
    idempotencyKey _: String
  ) async throws -> PlatformArchivePrepared {
    prepareCount += 1
    return PlatformArchivePrepared(
      operationID: UUID(uuidString: "00000000-0000-0000-0000-000000000115")!
    )
  }
  func openTransfer(
    provider _: PlatformArchiveProvider, operationID _: UUID,
    declaration _: BlobUploadDeclaration, idempotencyKey _: String
  ) async throws -> BlobUploadSession { throw PlatformDeviceTransportError.unavailable }
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

final class BindingAwareTransport: @unchecked Sendable, PlatformArchiveOperationTransport {
  let journal: LocalArchiveJournal
  let entryID: UUID
  let operationID: UUID
  var events = [String]()

  init(journal: LocalArchiveJournal, entryID: UUID, operationID: UUID) {
    self.journal = journal
    self.entryID = entryID
    self.operationID = operationID
  }

  func prepare(
    provider _: PlatformArchiveProvider, fingerprint _: ArchiveFingerprint,
    idempotencyKey _: String
  ) async throws -> PlatformArchivePrepared {
    events.append("prepare")
    return PlatformArchivePrepared(operationID: operationID)
  }
  func openTransfer(
    provider _: PlatformArchiveProvider, operationID _: UUID,
    declaration: BlobUploadDeclaration, idempotencyKey _: String
  ) async throws -> BlobUploadSession {
    events.append("transfer")
    XCTAssertEqual(journal.entries.first(where: { $0.id == entryID })?.operationID, operationID)
    return BlobUploadSession(token: "binding", chunkSizeBytes: declaration.chunkSizeBytes)
  }
  func transferStatus(
    provider _: PlatformArchiveProvider, operationID _: UUID, token _: String
  ) async throws -> BlobUploadStatus { BlobUploadStatus(receivedIndices: []) }
  func sendChunk(
    provider _: PlatformArchiveProvider, operationID _: UUID,
    token _: String, index _: Int, bytes _: Data
  ) async throws {}
  func finalizeTransfer(
    provider _: PlatformArchiveProvider, operationID _: UUID, token _: String
  ) async throws -> BlobStoredReceipt {
    let fingerprint = journal.entries.first(where: { $0.id == entryID })!.fingerprint
    return BlobStoredReceipt(
      sha256Hex: fingerprint.sha256Hex, byteSize: fingerprint.byteSize, reference: "stored"
    )
  }
}
