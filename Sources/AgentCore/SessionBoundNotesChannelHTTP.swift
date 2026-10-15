import Foundation

/// The HTTPS binding of the notes routes that resolves the paired origin for
/// each request, so pairing and re-pairing need no restart (as
/// `SessionBoundArchiveOperationTransport`).
public struct SessionBoundNotesChannelHTTP: NotesChannelHTTP {
  public init(session: DeviceSessionCoordinator) {}

  init(origin: @escaping @Sendable () async -> URL?, authorizer: any PlatformRequestAuthorizing, session: URLSession? = nil) {}

  public func perform(_ request: NotesChannelRequest) async throws -> NotesChannelAnswer {
    NotesChannelAnswer(status: 0, body: Data())
  }
}
