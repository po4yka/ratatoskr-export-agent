import AgentCore
import Foundation

actor VerticalOperationTransport: PlatformArchiveOperationTransport {
  private var operations: [UUID: (provider: PlatformArchiveProvider, fingerprint: ArchiveFingerprint)] = [:]
  private var received: [UUID: Set<Int>] = [:]
  private var didInterruptClaude = false
  private(set) var prepareCounts: [String: Int] = [:]
  private(set) var claudeStatusCount = 0

  func prepare(
    provider: PlatformArchiveProvider,
    fingerprint: ArchiveFingerprint,
    idempotencyKey _: String
  ) async throws -> PlatformArchivePrepared {
    let operationID = UUID()
    operations[operationID] = (provider, fingerprint)
    prepareCounts[provider.rawValue, default: 0] += 1
    return PlatformArchivePrepared(operationID: operationID)
  }

  func openTransfer(
    provider _: PlatformArchiveProvider, operationID: UUID,
    declaration _: BlobUploadDeclaration, idempotencyKey _: String
  ) async throws -> BlobUploadSession {
    BlobUploadSession(token: operationID.uuidString, chunkSizeBytes: 64 * 1024)
  }

  func transferStatus(
    provider: PlatformArchiveProvider, operationID: UUID, token _: String
  ) async throws -> BlobUploadStatus {
    if provider == .claude { claudeStatusCount += 1 }
    return BlobUploadStatus(receivedIndices: received[operationID, default: []])
  }

  func sendChunk(
    provider: PlatformArchiveProvider, operationID: UUID,
    token _: String, index: Int, bytes _: Data
  ) async throws {
    if provider == .claude, !didInterruptClaude {
      didInterruptClaude = true
      throw PlatformDeviceTransportError.unavailable
    }
    received[operationID, default: []].insert(index)
  }

  func finalizeTransfer(
    provider _: PlatformArchiveProvider, operationID: UUID, token _: String
  ) async throws -> BlobStoredReceipt {
    guard let fingerprint = operations[operationID]?.fingerprint else {
      throw VerticalFixtureError.unknownOperation
    }
    return BlobStoredReceipt(
      sha256Hex: fingerprint.sha256Hex,
      byteSize: fingerprint.byteSize,
      reference: "stored-\(operationID.uuidString)"
    )
  }
}

enum VerticalFixtureError: Error {
  case unknownOperation
}

struct VerticalOperationPoller: BackendOperationPolling {
  let providers: [UUID: PlatformArchiveProvider]

  func fetchOperation(_ operationID: UUID) async throws -> Data {
    guard let provider = providers[operationID] else { throw PlatformDeviceTransportError.unavailable }
    return Data("""
    {"status":"succeeded","results":[{"result_kind":"ai_archive.import",
    "target":"ai_archive:00000000-0000-0000-0000-000000000321",
    "ai_archive_import_summary":{"ai_archive_id":"00000000-0000-0000-0000-000000000321",
    "provider":"\(provider.rawValue)","completeness":"complete","conversation_count":1,
    "message_count":1,"asset_count":0,"gap_count":0,"warning_count":0}}]}
    """.utf8)
  }
}

actor VerticalNotificationService: AgentNotificationServing {
  private(set) var delivered: [AgentNotification] = []

  func authorization() async -> ImportNotificationAuthorization { .authorized }
  func deliver(_ notice: AgentNotification) async throws { delivered.append(notice) }
}
