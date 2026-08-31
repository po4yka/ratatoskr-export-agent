import AgentCore
import Foundation
import XCTest

final class ImportNotificationTests: XCTestCase {
  func testDeniedAuthorizationDoesNotDeliverTerminalNotice() async throws {
    let (journal, entry) = try terminalEntry()
    let service = RecordingNotificationService(authorization: .deniedOrUnavailable)
    let coordinator = ImportNotificationCoordinator(journal: journal, service: service)

    let delivered = await coordinator.notifyIfNeeded(entryID: entry.id)
    let notices = await service.delivered
    XCTAssertFalse(delivered)
    XCTAssertEqual(notices, [])
    XCTAssertFalse(journal.entries.first?.backendImport?.terminalNoticeDelivered ?? true)
  }

  func testAuthorizedTerminalObservationDeliversOneGenericNotice() async throws {
    let (journal, entry) = try terminalEntry()
    let service = RecordingNotificationService(authorization: .authorized)
    let coordinator = ImportNotificationCoordinator(journal: journal, service: service)

    let firstDelivery = await coordinator.notifyIfNeeded(entryID: entry.id)
    let secondDelivery = await coordinator.notifyIfNeeded(entryID: entry.id)
    XCTAssertTrue(firstDelivery)
    XCTAssertFalse(secondDelivery)
    let notices = await service.delivered
    XCTAssertEqual(notices, [AgentNotification(presentation: .importedWithGaps(gapCount: 2))])
    XCTAssertFalse(notices[0].title.contains("chatgpt"))
    XCTAssertFalse(notices[0].body.contains("2"))
    XCTAssertTrue(journal.entries.first?.backendImport?.terminalNoticeDelivered ?? false)
  }

  func testConcurrentAuthorizedChecksDeliverOnlyOneTerminalNotice() async throws {
    let (journal, entry) = try terminalEntry()
    let service = GatedNotificationService()
    let coordinator = NotificationCoordinatorBox(
      ImportNotificationCoordinator(journal: journal, service: service)
    )

    async let first = coordinator.value.notifyIfNeeded(entryID: entry.id)
    async let second = coordinator.value.notifyIfNeeded(entryID: entry.id)
    await service.waitForFirstDelivery()
    for _ in 0 ..< 10 { await Task.yield() }

    let deliveryCount = await service.deliveryCount
    XCTAssertEqual(deliveryCount, 1)
    await service.releaseDeliveries()
    let results = await [first, second]
    XCTAssertEqual(results.filter { $0 }.count, 1)
  }

  private func terminalEntry() throws -> (LocalArchiveJournal, JournalEntry) {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathComponent("journal.ndjson")
    let journal = try LocalArchiveJournal.open(at: url)
    let fingerprint = ArchiveFingerprint(sha256Hex: String(repeating: "b", count: 64), byteSize: 1)
    let discovered = try journal.discover(fingerprint: fingerprint, routing: fixtureRouting())
    let archived = try journal.advance(entryID: discovered.id, to: .archived)
    let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    _ = try journal.bindBackendOperation(entryID: archived.id, operationID: operationID)
    let entry = try journal.recordBackendObservation(
      entryID: archived.id, operationID: operationID,
      presentation: .importedWithGaps(gapCount: 2), observedAt: Date(timeIntervalSince1970: 1)
    )
    return (journal, entry)
  }
}

private actor RecordingNotificationService: AgentNotificationServing {
  let configuredAuthorization: ImportNotificationAuthorization
  var notices: [AgentNotification] = []

  init(authorization: ImportNotificationAuthorization) {
    configuredAuthorization = authorization
  }

  var delivered: [AgentNotification] { notices }

  func authorization() async -> ImportNotificationAuthorization { configuredAuthorization }

  func deliver(_ notice: AgentNotification) async throws { notices.append(notice) }
}

private actor GatedNotificationService: AgentNotificationServing {
  private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
  private var deliveryWaiters: [CheckedContinuation<Void, Never>] = []
  private var firstDeliveryWaiters: [CheckedContinuation<Void, Never>] = []
  private(set) var authorizationCount = 0
  private(set) var deliveryCount = 0

  func authorization() async -> ImportNotificationAuthorization {
    authorizationCount += 1
    if authorizationCount < 2 {
      await withCheckedContinuation { authorizationWaiters.append($0) }
    } else {
      let waiters = authorizationWaiters
      authorizationWaiters.removeAll()
      waiters.forEach { $0.resume() }
    }
    return .authorized
  }

  func deliver(_: AgentNotification) async throws {
    deliveryCount += 1
    if deliveryCount == 1 {
      let waiters = firstDeliveryWaiters
      firstDeliveryWaiters.removeAll()
      waiters.forEach { $0.resume() }
    }
    await withCheckedContinuation { deliveryWaiters.append($0) }
  }

  func waitForFirstDelivery() async {
    guard deliveryCount == 0 else { return }
    await withCheckedContinuation { firstDeliveryWaiters.append($0) }
  }

  func releaseDeliveries() {
    let waiters = deliveryWaiters
    deliveryWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }
}

private final class NotificationCoordinatorBox: @unchecked Sendable {
  let value: ImportNotificationCoordinator

  init(_ value: ImportNotificationCoordinator) {
    self.value = value
  }
}
