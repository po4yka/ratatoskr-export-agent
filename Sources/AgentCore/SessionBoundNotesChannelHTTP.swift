import Foundation

/// The HTTPS binding of the notes routes that resolves the paired origin for
/// each request, so pairing and re-pairing need no restart (as
/// `SessionBoundArchiveOperationTransport`). One URL session serves every
/// request.
public struct SessionBoundNotesChannelHTTP: NotesChannelHTTP {
  private let origin: @Sendable () async -> URL?
  private let authorizer: any PlatformRequestAuthorizing
  private let session: URLSession

  public init(session coordinator: DeviceSessionCoordinator) {
    self.init(
      origin: { await coordinator.pairedIdentity()?.origin },
      authorizer: coordinator,
      session: URLSession(configuration: .ephemeral, delegate: PlatformRedirectBlocker(), delegateQueue: nil)
    )
  }

  init(origin: @escaping @Sendable () async -> URL?, authorizer: any PlatformRequestAuthorizing, session: URLSession? = nil) {
    self.origin = origin
    self.authorizer = authorizer
    self.session = session ?? URLSession(configuration: .ephemeral, delegate: PlatformRedirectBlocker(), delegateQueue: nil)
  }

  public func perform(_ request: NotesChannelRequest) async throws -> NotesChannelAnswer {
    guard let origin = await origin() else {
      throw DeviceCredentialError.unavailable
    }
    return try await PlatformNotesChannelHTTP(origin: origin, authorizer: authorizer, session: session).perform(request)
  }
}
