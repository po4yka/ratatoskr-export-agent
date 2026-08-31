import Foundation

struct AuthenticatedPlatformHTTPClient: Sendable {
  private let authorizer: any PlatformRequestAuthorizing
  private let session: URLSession

  init(authorizer: any PlatformRequestAuthorizing, session: URLSession) {
    self.authorizer = authorizer
    self.session = session
  }

  func perform(_ unsignedRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let firstCredential = try await authorizer.credentialForRequest()
    let first = try await send(unsignedRequest, credential: firstCredential)
    guard first.1.statusCode == 401 else { return first }

    let recovered = try await authorizer.recoverCredential(
      afterRejectedCredential: firstCredential
    )
    let second = try await send(unsignedRequest, credential: recovered)
    if second.1.statusCode == 401 {
      await authorizer.authorizationWasRejected(recovered)
    }
    return second
  }

  private func send(
    _ unsignedRequest: URLRequest,
    credential: String
  ) async throws -> (Data, HTTPURLResponse) {
    var request = unsignedRequest
    request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
    let result: (Data, URLResponse)
    do {
      result = try await session.data(for: request)
    } catch {
      throw PlatformDeviceTransportError.unavailable
    }
    guard let response = result.1 as? HTTPURLResponse else {
      throw PlatformDeviceTransportError.invalidResponse
    }
    return (result.0, response)
  }
}
