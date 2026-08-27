import Foundation

public enum PlatformDeviceTransportError: Error, CustomStringConvertible, Sendable {
  case invalidOrigin
  case refused
  case invalidResponse
  case unavailable

  public var description: String {
    switch self {
    case .invalidOrigin:
      "The configured Platform origin is invalid."
    case .refused:
      "Platform did not accept the device credential."
    case .invalidResponse:
      "Platform returned an invalid device response."
    case .unavailable:
      "Platform is unavailable."
    }
  }
}

public struct URLSessionPlatformDeviceTransport: PlatformDeviceTransport {
  let session: URLSession
  private let redirectBlocker: PlatformRedirectBlocker?

  public init() {
    let blocker = PlatformRedirectBlocker()
    redirectBlocker = blocker
    session = URLSession(
      configuration: .ephemeral,
      delegate: blocker,
      delegateQueue: nil
    )
  }

  init(session: URLSession) {
    self.session = session
    redirectBlocker = nil
  }

  public func pair(_ request: DevicePairingRequest) async throws -> DevicePairingResponse {
    guard let endpoint = Self.endpoint(for: request.origin, path: "v1/devices/pair") else {
      throw PlatformDeviceTransportError.invalidOrigin
    }
    let body = PairRequestBody(
      code: request.code,
      kind: request.kind,
      displayName: request.displayName
    )
    var urlRequest = URLRequest(url: endpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try JSONEncoder().encode(body)

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: urlRequest)
    } catch {
      throw PlatformDeviceTransportError.unavailable
    }
    guard let httpResponse = response as? HTTPURLResponse else {
      throw PlatformDeviceTransportError.invalidResponse
    }
    guard httpResponse.statusCode == 201 else {
      throw httpResponse.statusCode == 401
        ? PlatformDeviceTransportError.refused : PlatformDeviceTransportError.unavailable
    }
    return try Self.decodePairing(data, origin: request.origin)
  }

  static func endpoint(for origin: URL, path: String) -> URL? {
    guard origin.scheme?.lowercased() == "https", origin.host != nil,
          origin.user == nil, origin.password == nil,
          origin.path.isEmpty || origin.path == "/",
          origin.query == nil, origin.fragment == nil else {
      return nil
    }
    return origin.appending(path: path)
  }

  func post(_ request: URLRequest, expecting statusCode: Int) async throws -> Data {
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw PlatformDeviceTransportError.unavailable
    }
    guard let httpResponse = response as? HTTPURLResponse else {
      throw PlatformDeviceTransportError.invalidResponse
    }
    guard httpResponse.statusCode == statusCode else {
      throw httpResponse.statusCode == 401
        ? PlatformDeviceTransportError.refused : PlatformDeviceTransportError.unavailable
    }
    return data
  }

  private static func decodePairing(_ data: Data, origin: URL) throws -> DevicePairingResponse {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let response = try decoder.decode(PairedDeviceBody.self, from: data)
    guard let deviceID = UUID(uuidString: response.deviceID),
          let userID = UUID(uuidString: response.userID) else {
      throw PlatformDeviceTransportError.invalidResponse
    }
    let identity = PairedDeviceIdentity(
      origin: origin,
      deviceID: deviceID,
      userID: userID,
      credentialExpiresAt: response.expiresAt
    )
    let credentials = DeviceCredentialSet(
      deviceSecret: response.deviceSecret,
      accessCredential: response.credential,
      refreshToken: response.refreshToken,
      refreshExpiresAt: response.refreshExpiresAt
    )
    return DevicePairingResponse(identity: identity, credentials: credentials)
  }
}

final class PlatformRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

private struct PairRequestBody: Encodable {
  let code: String
  let kind: String
  let displayName: String?

  enum CodingKeys: String, CodingKey {
    case code
    case kind
    case displayName = "display_name"
  }
}

private struct PairedDeviceBody: Decodable {
  let deviceID: String
  let userID: String
  let deviceSecret: String
  let credential: String
  let expiresAt: Date
  let refreshToken: String
  let refreshExpiresAt: Date

  enum CodingKeys: String, CodingKey {
    case deviceID = "device_id"
    case userID = "user_id"
    case deviceSecret = "device_secret"
    case credential
    case expiresAt = "expires_at"
    case refreshToken = "refresh_token"
    case refreshExpiresAt = "refresh_expires_at"
  }
}
