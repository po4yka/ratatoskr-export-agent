import Foundation

struct AuthenticatedPlatformHTTPClient: Sendable {
  private let authorizer: any PlatformRequestAuthorizing
  private let session: URLSession

  init(authorizer: any PlatformRequestAuthorizing, session: URLSession) {
    self.authorizer = authorizer
    self.session = session
  }

  /// Sends the request with the device credential. With `bound`, at most
  /// `bound` and one byte of the body are read, so a caller sees that a body
  /// passes the bound without holding all of it.
  func perform(_ unsignedRequest: URLRequest, bound: Int? = nil) async throws -> (Data, HTTPURLResponse) {
    let firstCredential = try await authorizer.credentialForRequest()
    let first = try await send(unsignedRequest, credential: firstCredential, bound: bound)
    guard first.1.statusCode == 401 else { return first }

    let recovered = try await authorizer.recoverCredential(
      afterRejectedCredential: firstCredential
    )
    let second = try await send(unsignedRequest, credential: recovered, bound: bound)
    if second.1.statusCode == 401, PlatformAuthVerdict.isPlatformUnauthenticated(second.0) {
      await authorizer.authorizationWasRejected(recovered)
    }
    return second
  }

  private func send(
    _ unsignedRequest: URLRequest,
    credential: String,
    bound: Int?
  ) async throws -> (Data, HTTPURLResponse) {
    var request = unsignedRequest
    request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
    let result: (Data, URLResponse)
    do {
      if let bound {
        result = try await read(request, bound: bound)
      } else {
        result = try await session.data(for: request)
      }
    } catch {
      throw PlatformDeviceTransportError.unavailable
    }
    guard let response = result.1 as? HTTPURLResponse else {
      throw PlatformDeviceTransportError.invalidResponse
    }
    return (result.0, response)
  }

  /// Reads at most `bound` and one byte of the body, then cancels the rest.
  private func read(_ request: URLRequest, bound: Int) async throws -> (Data, URLResponse) {
    let (bytes, response) = try await session.bytes(for: request)
    var data = Data()
    for try await byte in bytes {
      data.append(byte)
      if data.count > bound {
        bytes.task.cancel()
        break
      }
    }
    return (data, response)
  }
}
