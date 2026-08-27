import Foundation

/// HTTPS client for Platform's operation-bound archive endpoints.
public struct URLSessionPlatformArchiveOperationTransport: PlatformArchiveOperationTransport {
  private let origin: URL
  private let accessCredential: String
  private let session: URLSession

  public init(origin: URL, accessCredential: String) {
    self.origin = origin
    self.accessCredential = accessCredential
    let blocker = PlatformRedirectBlocker()
    session = URLSession(configuration: .ephemeral, delegate: blocker, delegateQueue: nil)
  }

  init(origin: URL, accessCredential: String, session: URLSession) {
    self.origin = origin
    self.accessCredential = accessCredential
    self.session = session
  }

  public func prepare(
    provider: PlatformArchiveProvider,
    fingerprint: ArchiveFingerprint,
    idempotencyKey: String
  ) async throws -> PlatformArchivePrepared {
    guard let endpoint = URLSessionPlatformDeviceTransport.endpoint(
      for: origin, path: "v1/ai-archives/\(provider.rawValue)"
    ) else { throw PlatformDeviceTransportError.invalidOrigin }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessCredential)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
    request.httpBody = try JSONEncoder().encode(PrepareBody(
      sha256: fingerprint.sha256Hex, byteSize: fingerprint.byteSize
    ))
    let (data, response) = try await perform(request)
    guard response.statusCode == 202 else { throw response.error }
    let prepared: PrepareResponse
    do { prepared = try JSONDecoder().decode(PrepareResponse.self, from: data) }
    catch { throw PlatformDeviceTransportError.invalidResponse }
    guard prepared.status == "accepted", let operationID = UUID(uuidString: prepared.operationID),
          prepared.uploadPath == "/v1/ai-archives/\(provider.rawValue)/\(operationID.uuidString.lowercased())/content"
    else { throw PlatformDeviceTransportError.invalidResponse }
    return PlatformArchivePrepared(operationID: operationID, uploadPath: prepared.uploadPath)
  }

  public func transfer(
    provider _: PlatformArchiveProvider,
    prepared: PlatformArchivePrepared,
    archiveURL: URL,
    fingerprint _: ArchiveFingerprint
  ) async throws {
    guard let endpoint = URLSessionPlatformDeviceTransport.endpoint(
      for: origin, path: String(prepared.uploadPath.dropFirst())
    ) else { throw PlatformDeviceTransportError.invalidOrigin }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "PUT"
    request.setValue("Bearer \(accessCredential)", forHTTPHeaderField: "Authorization")
    request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
    let (_, response): (Data, URLResponse)
    do { (_, response) = try await session.upload(for: request, fromFile: archiveURL) }
    catch { throw PlatformDeviceTransportError.unavailable }
    guard let response = response as? HTTPURLResponse else {
      throw PlatformDeviceTransportError.invalidResponse
    }
    guard (200 ..< 300).contains(response.statusCode) else { throw response.error }
  }

  private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let data: Data
    let response: URLResponse
    do { (data, response) = try await session.data(for: request) }
    catch { throw PlatformDeviceTransportError.unavailable }
    guard let response = response as? HTTPURLResponse else {
      throw PlatformDeviceTransportError.invalidResponse
    }
    return (data, response)
  }
}

private extension HTTPURLResponse {
  var error: PlatformDeviceTransportError {
    statusCode == 401 ? .refused : .unavailable
  }
}

private struct PrepareBody: Encodable {
  let sha256: String
  let byteSize: Int
  enum CodingKeys: String, CodingKey { case sha256; case byteSize = "byte_size" }
}

private struct PrepareResponse: Decodable {
  let operationID: String
  let status: String
  let uploadPath: String
  enum CodingKeys: String, CodingKey {
    case operationID = "operation_id"; case status; case uploadPath = "upload_path"
  }
}
