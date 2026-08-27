import Foundation

/// The only notification authorization states relevant to the agent.
public enum ImportNotificationAuthorization: Sendable {
  case authorized
  case deniedOrUnavailable
}

public struct AgentNotification: Equatable, Sendable {
  public let title: String
  public let body: String

  public init(title: String, body: String) {
    self.title = title
    self.body = body
  }

  public static let watchedItemsNeedAttention = AgentNotification(
    title: "Watched items need attention",
    body: "Open Ratatoskr to review watched items."
  )
}

public protocol AgentNotificationServing: Sendable {
  func authorization() async -> ImportNotificationAuthorization
  func deliver(_ notice: AgentNotification) async throws
}
