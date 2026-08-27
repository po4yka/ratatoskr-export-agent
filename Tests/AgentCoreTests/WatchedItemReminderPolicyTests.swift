import Foundation
import XCTest

@testable import AgentCore

final class WatchedItemReminderPolicyTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let threshold: TimeInterval = 3_600

  func testItemAtThresholdMakesEnabledFolderEligible() throws {
    let policy = try WatchedItemReminderPolicy(threshold: threshold)
    let folder = WatchedFolderReminderObservation(
      id: UUID(),
      isEnabled: true,
      items: [
        WatchedItemReminderObservation(
          discoveredAt: now.addingTimeInterval(-threshold),
          isProcessed: false,
        ),
      ]
    )

    XCTAssertTrue(policy.isEligible(folder, at: now))
  }

  func testRecentProcessedAndDisabledItemsStayIneligible() throws {
    let policy = try WatchedItemReminderPolicy(threshold: threshold)
    let recent = WatchedFolderReminderObservation(
      id: UUID(),
      isEnabled: true,
      items: [.init(discoveredAt: now.addingTimeInterval(-threshold + 1), isProcessed: false)]
    )
    let processed = WatchedFolderReminderObservation(
      id: UUID(),
      isEnabled: true,
      items: [.init(discoveredAt: now.addingTimeInterval(-threshold), isProcessed: true)]
    )
    let disabled = WatchedFolderReminderObservation(
      id: UUID(),
      isEnabled: false,
      items: [.init(discoveredAt: now.addingTimeInterval(-threshold), isProcessed: false)]
    )

    XCTAssertFalse(policy.isEligible(recent, at: now))
    XCTAssertFalse(policy.isEligible(processed, at: now))
    XCTAssertFalse(policy.isEligible(disabled, at: now))
  }

  func testContinuingConditionIsSuppressedUntilCleared() async throws {
    let folderID = UUID()
    let store = MemoryReminderStateStore()
    let service = RecordingAgentNotificationService(authorization: .authorized)
    let coordinator = try WatchedItemReminderCoordinator(
      policy: WatchedItemReminderPolicy(threshold: threshold),
      stateStore: store,
      notificationService: service
    )

    let first = try await coordinator.evaluate([staleFolder(id: folderID)], at: now)
    let repeated = try await coordinator.evaluate([staleFolder(id: folderID)], at: now)
    let cleared = try await coordinator.evaluate([emptyFolder(id: folderID)], at: now)
    let rearmed = try await coordinator.evaluate([staleFolder(id: folderID)], at: now)

    XCTAssertEqual(first, 1)
    XCTAssertEqual(repeated, 0)
    XCTAssertEqual(cleared, 0)
    XCTAssertEqual(rearmed, 1)
    let delivered = await service.delivered
    XCTAssertEqual(delivered, [.watchedItemsNeedAttention, .watchedItemsNeedAttention])
  }

  func testSnoozeAndDeniedPermissionSuppressDelivery() async throws {
    let folderID = UUID()
    let snoozedStore = MemoryReminderStateStore(
      state: .init(
        folders: [
          .init(
            folderID: folderID,
            deliveredForCurrentCondition: false,
            snoozedUntil: now.addingTimeInterval(60),
          ),
        ],
        lastEvaluatedAt: nil
      )
    )
    let authorized = RecordingAgentNotificationService(authorization: .authorized)
    let snoozed = try WatchedItemReminderCoordinator(
      policy: WatchedItemReminderPolicy(threshold: threshold),
      stateStore: snoozedStore,
      notificationService: authorized
    )
    let denied = try WatchedItemReminderCoordinator(
      policy: WatchedItemReminderPolicy(threshold: threshold),
      stateStore: MemoryReminderStateStore(),
      notificationService: RecordingAgentNotificationService(authorization: .deniedOrUnavailable)
    )

    let snoozedDeliveryCount = try await snoozed.evaluate([staleFolder(id: folderID)], at: now)
    let deniedDeliveryCount = try await denied.evaluate([staleFolder(id: UUID())], at: now)

    XCTAssertEqual(snoozedDeliveryCount, 0)
    XCTAssertEqual(deniedDeliveryCount, 0)
    let delivered = await authorized.delivered
    XCTAssertTrue(delivered.isEmpty)
  }

  func testReminderStateRoundTripsWithoutFolderCoordinates() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let url = directory.appendingPathComponent("reminders.json")
    let store = FileWatchedItemReminderStateStore(fileURL: url)
    let state = WatchedItemReminderStateDocument(
      folders: [.init(folderID: UUID(), deliveredForCurrentCondition: true, snoozedUntil: nil)],
      lastEvaluatedAt: now
    )

    try store.save(state)

    XCTAssertEqual(try store.load(), state)
    let encoded = try String(contentsOf: url, encoding: .utf8)
    XCTAssertFalse(encoded.contains("private-export.zip"))
    XCTAssertFalse(encoded.contains("/Users/private"))
  }

  private func staleFolder(id: UUID) -> WatchedFolderReminderObservation {
    .init(
      id: id,
      isEnabled: true,
      items: [.init(discoveredAt: now.addingTimeInterval(-threshold), isProcessed: false)]
    )
  }

  private func emptyFolder(id: UUID) -> WatchedFolderReminderObservation {
    .init(id: id, isEnabled: true, items: [])
  }
}

private final class MemoryReminderStateStore: WatchedItemReminderStateStoring, @unchecked Sendable {
  var state: WatchedItemReminderStateDocument

  init(state: WatchedItemReminderStateDocument = .init()) {
    self.state = state
  }

  func load() throws -> WatchedItemReminderStateDocument { state }
  func save(_ state: WatchedItemReminderStateDocument) throws { self.state = state }
}

private actor RecordingAgentNotificationService: AgentNotificationServing {
  let authorizationValue: ImportNotificationAuthorization
  var delivered: [AgentNotification] = []

  init(authorization: ImportNotificationAuthorization) {
    authorizationValue = authorization
  }

  func authorization() async -> ImportNotificationAuthorization { authorizationValue }
  func deliver(_ notice: AgentNotification) async throws { delivered.append(notice) }
}
