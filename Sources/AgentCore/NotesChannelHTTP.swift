import Foundation

/// One request on a device route of `ratatoskr-notes` behind Edge. `path` is
/// relative to the paired origin, for example `v1/notes/connections`.
public struct NotesChannelRequest: Equatable, Sendable {
  public let method: String
  public let path: String
  public let body: Data?
  public let contentType: String?

  public init(method: String, path: String, body: Data? = nil, contentType: String? = nil) {
    self.method = method
    self.path = path
    self.body = body
    self.contentType = contentType
  }
}

/// The status and the body of an answer.
public struct NotesChannelAnswer: Equatable, Sendable {
  public let status: Int
  public let body: Data

  public init(status: Int, body: Data) {
    self.status = status
    self.body = body
  }
}

/// Sends one request with the device credential and gives the answer.
public protocol NotesChannelHTTP: Sendable {
  func perform(_ request: NotesChannelRequest) async throws -> NotesChannelAnswer
}

/// The HTTPS binding: the paired origin, the device credential of the session,
/// and no redirects.
public struct PlatformNotesChannelHTTP: NotesChannelHTTP {
  private let origin: URL
  private let client: AuthenticatedPlatformHTTPClient

  public init(origin: URL, authorizer: any PlatformRequestAuthorizing) {
    let session = URLSession(configuration: .ephemeral, delegate: PlatformRedirectBlocker(), delegateQueue: nil)
    self.init(origin: origin, authorizer: authorizer, session: session)
  }

  init(origin: URL, authorizer: any PlatformRequestAuthorizing, session: URLSession) {
    self.origin = origin
    client = AuthenticatedPlatformHTTPClient(authorizer: authorizer, session: session)
  }

  public func perform(_ request: NotesChannelRequest) async throws -> NotesChannelAnswer {
    guard let endpoint = URLSessionPlatformDeviceTransport.endpoint(for: origin, path: request.path) else {
      throw PlatformDeviceTransportError.invalidOrigin
    }
    var unsigned = URLRequest(url: endpoint)
    unsigned.httpMethod = request.method
    unsigned.httpBody = request.body
    if let contentType = request.contentType {
      unsigned.setValue(contentType, forHTTPHeaderField: "Content-Type")
    }
    let (data, response) = try await client.perform(unsigned)
    return NotesChannelAnswer(status: response.statusCode, body: data)
  }
}
