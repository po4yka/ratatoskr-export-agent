import Foundation

/// Strict HTTPS client for Platform's operation-owned resumable archive routes.
public struct PlatformArchiveHTTPTransport: PlatformArchiveOperationTransport {
  private let origin: URL
  private let client: AuthenticatedPlatformHTTPClient

  public init(origin: URL, authorizer: any PlatformRequestAuthorizing) {
    self.origin = origin
    let blocker = PlatformRedirectBlocker()
    let session = URLSession(configuration: .ephemeral, delegate: blocker, delegateQueue: nil)
    client = AuthenticatedPlatformHTTPClient(authorizer: authorizer, session: session)
  }

  init(
    origin: URL,
    authorizer: any PlatformRequestAuthorizing,
    session: URLSession
  ) {
    self.origin = origin
    client = AuthenticatedPlatformHTTPClient(authorizer: authorizer, session: session)
  }

  public func prepare(
    provider: PlatformArchiveProvider, fingerprint: ArchiveFingerprint, idempotencyKey: String
  ) async throws -> PlatformArchivePrepared {
    var request = try request(path: "v1/ai-archives/\(provider.rawValue)", method: "POST")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
    request.httpBody = try JSONEncoder().encode(
      PrepareBody(
        sha256: fingerprint.sha256Hex, byteSize: fingerprint.byteSize
      ))
    let (data, response) = try await perform(request)
    guard response.statusCode == 202 else { throw response.transportError }
    let body = try decode(PrepareResponse.self, from: data)
    guard body.status == "accepted", let operationID = UUID(uuidString: body.operationID) else {
      throw PlatformDeviceTransportError.invalidResponse
    }
    return PlatformArchivePrepared(operationID: operationID)
  }

  public func openTransfer(
    provider: PlatformArchiveProvider, operationID: UUID,
    declaration: BlobUploadDeclaration, idempotencyKey: String
  ) async throws -> BlobUploadSession {
    var request = try request(path: transferPath(provider, operationID), method: "POST")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
    request.httpBody = try JSONEncoder().encode(declaration)
    let (data, response) = try await perform(request)
    guard response.statusCode == 201 || response.statusCode == 200 else {
      throw response.transportError
    }
    let body = try decode(OpenTransferResponse.self, from: data)
    guard !body.resumptionToken.isEmpty, body.chunkSizeBytes > 0 else {
      throw PlatformDeviceTransportError.invalidResponse
    }
    return BlobUploadSession(token: body.resumptionToken, chunkSizeBytes: body.chunkSizeBytes)
  }

  public func transferStatus(
    provider: PlatformArchiveProvider, operationID: UUID, token: String
  ) async throws -> BlobUploadStatus {
    let request = try request(
      path: "\(transferPath(provider, operationID))/\(token)/status", method: "GET"
    )
    let (data, response) = try await perform(request)
    guard response.statusCode == 200 else { throw response.transportError }
    let body = try decode(TransferStatusResponse.self, from: data)
    guard body.resumptionToken == token else {
      throw PlatformDeviceTransportError.invalidResponse
    }
    return BlobUploadStatus(receivedIndices: Set(body.receivedChunks))
  }

  public func sendChunk(
    provider: PlatformArchiveProvider, operationID: UUID, token: String,
    index: Int, bytes: Data
  ) async throws {
    var request = try request(
      path: "\(transferPath(provider, operationID))/\(token)/chunks/\(index)", method: "PUT"
    )
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    request.httpBody = bytes
    let (_, response) = try await perform(request)
    guard response.statusCode == 204 || response.statusCode == 200 else {
      throw response.transportError
    }
  }

  public func finalizeTransfer(
    provider: PlatformArchiveProvider, operationID: UUID, token: String
  ) async throws -> BlobStoredReceipt {
    var request = try request(
      path: "\(transferPath(provider, operationID))/\(token)/finalize", method: "POST"
    )
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(FinalizeRequest(resumptionToken: token))
    let (data, response) = try await perform(request)
    guard response.statusCode == 200 else { throw response.transportError }
    let body = try decode(FinalizeResponse.self, from: data)
    guard body.outcome == "stored", let blob = body.blobRef,
      blob.digest.algorithm == "sha256"
    else {
      throw BlobReceiptTransportError.invalidReceipt
    }
    return BlobStoredReceipt(
      sha256Hex: blob.digest.hex,
      byteSize: blob.lengthBytes,
      reference: "\(blob.ownerService):sha256:\(blob.digest.hex)"
    )
  }

  private func request(path: String, method: String) throws -> URLRequest {
    guard let endpoint = URLSessionPlatformDeviceTransport.endpoint(for: origin, path: path) else {
      throw PlatformDeviceTransportError.invalidOrigin
    }
    var request = URLRequest(url: endpoint)
    request.httpMethod = method
    return request
  }

  private func transferPath(_ provider: PlatformArchiveProvider, _ operationID: UUID) -> String {
    "v1/ai-archives/\(provider.rawValue)/\(operationID.uuidString.lowercased())/uploads"
  }

  private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    try await client.perform(request)
  }

  private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
    do { return try JSONDecoder().decode(type, from: data) } catch {
      throw PlatformDeviceTransportError.invalidResponse
    }
  }
}

extension HTTPURLResponse {
  fileprivate var transportError: PlatformDeviceTransportError {
    statusCode == 401 ? .refused : .unavailable
  }
}
