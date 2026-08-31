import Foundation

/// Resolves the paired HTTPS origin for every operation so pairing and re-pairing need no restart.
public struct SessionBoundArchiveOperationTransport: PlatformArchiveOperationTransport {
  private let session: DeviceSessionCoordinator

  public init(session: DeviceSessionCoordinator) { self.session = session }

  public func prepare(
    provider: PlatformArchiveProvider,
    fingerprint: ArchiveFingerprint,
    idempotencyKey: String
  ) async throws -> PlatformArchivePrepared {
    try await transport().prepare(
      provider: provider, fingerprint: fingerprint, idempotencyKey: idempotencyKey
    )
  }

  public func openTransfer(
    provider: PlatformArchiveProvider,
    operationID: UUID,
    declaration: BlobUploadDeclaration,
    idempotencyKey: String
  ) async throws -> BlobUploadSession {
    try await transport().openTransfer(
      provider: provider, operationID: operationID,
      declaration: declaration, idempotencyKey: idempotencyKey
    )
  }

  public func transferStatus(
    provider: PlatformArchiveProvider, operationID: UUID, token: String
  ) async throws -> BlobUploadStatus {
    try await transport().transferStatus(
      provider: provider, operationID: operationID, token: token
    )
  }

  public func sendChunk(
    provider: PlatformArchiveProvider, operationID: UUID,
    token: String, index: Int, bytes: Data
  ) async throws {
    try await transport().sendChunk(
      provider: provider, operationID: operationID, token: token, index: index, bytes: bytes
    )
  }

  public func finalizeTransfer(
    provider: PlatformArchiveProvider, operationID: UUID, token: String
  ) async throws -> BlobStoredReceipt {
    try await transport().finalizeTransfer(
      provider: provider, operationID: operationID, token: token
    )
  }

  private func transport() async throws -> PlatformArchiveHTTPTransport {
    guard let origin = await session.pairedIdentity()?.origin else {
      throw DeviceCredentialError.unavailable
    }
    return PlatformArchiveHTTPTransport(origin: origin, authorizer: session)
  }
}

public struct SessionBoundBackendOperationPoller: BackendOperationPolling {
  private let session: DeviceSessionCoordinator

  public init(session: DeviceSessionCoordinator) { self.session = session }

  public func fetchOperation(_ operationID: UUID) async throws -> Data {
    guard let origin = await session.pairedIdentity()?.origin else {
      throw DeviceCredentialError.unavailable
    }
    return try await URLSessionBackendOperationPoller(
      origin: origin, authorizer: session
    ).fetchOperation(operationID)
  }
}
