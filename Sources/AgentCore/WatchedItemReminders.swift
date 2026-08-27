import Foundation

public enum WatchedItemReminderPolicyError: Error, Equatable, Sendable {
  case invalidThreshold
}

public struct WatchedItemReminderObservation: Equatable, Sendable {
  public let discoveredAt: Date
  public let isProcessed: Bool

  public init(discoveredAt: Date, isProcessed: Bool) {
    self.discoveredAt = discoveredAt
    self.isProcessed = isProcessed
  }
}

public struct WatchedFolderReminderObservation: Equatable, Sendable {
  public let id: UUID
  public let isEnabled: Bool
  public let items: [WatchedItemReminderObservation]

  public init(id: UUID, isEnabled: Bool, items: [WatchedItemReminderObservation]) {
    self.id = id
    self.isEnabled = isEnabled
    self.items = items
  }
}

public struct WatchedItemReminderPolicy: Sendable {
  public let threshold: TimeInterval

  public init(threshold: TimeInterval) throws {
    guard threshold > 0 else { throw WatchedItemReminderPolicyError.invalidThreshold }
    self.threshold = threshold
  }

  public func isEligible(_ folder: WatchedFolderReminderObservation, at now: Date) -> Bool {
    folder.isEnabled && folder.items.contains { item in
      !item.isProcessed && now.timeIntervalSince(item.discoveredAt) >= threshold
    }
  }
}
