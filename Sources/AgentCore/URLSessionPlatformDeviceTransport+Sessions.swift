import Foundation

extension URLSessionPlatformDeviceTransport {
  public func refresh(origin: URL, refreshToken: String) async throws -> DeviceSessionCredentials {
    let body = RefreshRequestBody(refreshToken: refreshToken)
    return try await sessionCredentials(
      origin: origin, path: "v1/sessions/refresh", body: body, statusCode: 200
    )
  }

  public func openSession(
    origin: URL, deviceID: UUID, deviceSecret: String
  ) async throws -> DeviceSessionCredentials {
    let body = OpenSessionRequestBody(deviceID: deviceID.uuidString, deviceSecret: deviceSecret)
    return try await sessionCredentials(
      origin: origin, path: "v1/sessions/device", body: body, statusCode: 201
    )
  }

  private func sessionCredentials<Body: Encodable>(
    origin: URL, path: String, body: Body, statusCode: Int
  ) async throws -> DeviceSessionCredentials {
    guard let endpoint = Self.endpoint(for: origin, path: path) else {
      throw PlatformDeviceTransportError.invalidOrigin
    }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)
    let data = try await post(request, expecting: statusCode)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let response = try decoder.decode(SessionCredentialsBody.self, from: data)
    return DeviceSessionCredentials(
      accessCredential: response.credential,
      credentialExpiresAt: response.expiresAt,
      refreshToken: response.refreshToken,
      refreshExpiresAt: response.refreshExpiresAt
    )
  }
}

private struct RefreshRequestBody: Encodable {
  let refreshToken: String
  enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
}

private struct OpenSessionRequestBody: Encodable {
  let deviceID: String
  let deviceSecret: String
  enum CodingKeys: String, CodingKey {
    case deviceID = "device_id"
    case deviceSecret = "device_secret"
  }
}

private struct SessionCredentialsBody: Decodable {
  let credential: String
  let expiresAt: Date
  let refreshToken: String
  let refreshExpiresAt: Date
  enum CodingKeys: String, CodingKey {
    case credential
    case expiresAt = "expires_at"
    case refreshToken = "refresh_token"
    case refreshExpiresAt = "refresh_expires_at"
  }
}
