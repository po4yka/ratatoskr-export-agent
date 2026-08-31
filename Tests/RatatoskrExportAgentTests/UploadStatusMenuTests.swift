import AgentCore
import XCTest

@testable import RatatoskrExportAgent

final class UploadStatusMenuTests: XCTestCase {
  @MainActor
  func testActiveQueuedUploadExposesPauseAndCancelActions() {
    let id = UUID()
    let entry = JournalEntry(
      id: id,
      fingerprint: ArchiveFingerprint(sha256Hex: String(repeating: "a", count: 64), byteSize: 1),
      idempotencyKey: "private-key",
      routing: appFixtureRouting(),
      state: .queued,
      uploadCheckpoint: UploadCheckpoint(chunkSizeBytes: 1)
    )
    let coordinator = AgentMenuCoordinator()
    let menu = AgentMenu.make(
      coordinator: coordinator, uploadStatus: UploadQueueStatus(entries: [entry])
    )

    let actions =
      menu.items.first { $0.tag == AgentMenu.uploadControlsItemTag }?.submenu?.items ?? []
    XCTAssertEqual(actions.map(\.title), ["Pause", "Cancel"])
    XCTAssertEqual(
      actions.map(\.action),
      [
        #selector(AgentMenuCoordinator.pauseUploadSelected(_:)),
        #selector(AgentMenuCoordinator.cancelUploadSelected(_:)),
      ]
    )
    XCTAssertTrue(actions.allSatisfy { ($0.representedObject as? UUID) == id })
  }

  @MainActor
  func testMenuShowsRedactedQueuedAndProgressState() {
    let entry = JournalEntry(
      id: UUID(),
      fingerprint: ArchiveFingerprint(sha256Hex: String(repeating: "d", count: 64), byteSize: 1),
      idempotencyKey: "key",
      routing: appFixtureRouting(),
      state: .queued,
      uploadCheckpoint: UploadCheckpoint(
        resumptionToken: "rst",
        chunkSizeBytes: 65536,
        nextRetryAt: .distantFuture
      )
    )
    let status = UploadQueueStatus(entries: [entry], now: .distantPast)
    let menu = AgentMenu.make(coordinator: AgentMenuCoordinator(), uploadStatus: status)
    let title = menu.items.first { $0.tag == AgentMenu.uploadStatusItemTag }?.title ?? ""
    XCTAssertEqual(title, "1 upload retry queued")
    XCTAssertFalse(title.contains(String(repeating: "d", count: 64)))
    XCTAssertFalse(title.contains("rst"))
  }

  @MainActor
  func testBindingUpdatesMenuFromRedactedQueueProjection() async {
    var continuation: AsyncStream<UploadQueueStatus>.Continuation?
    let updates = AsyncStream<UploadQueueStatus> { continuation = $0 }
    let menu = AgentMenu.make(coordinator: AgentMenuCoordinator())
    let binding = UploadMenuStatusBinding(menu: menu, updates: updates)
    let entry = JournalEntry(
      id: UUID(),
      fingerprint: ArchiveFingerprint(sha256Hex: String(repeating: "e", count: 64), byteSize: 100),
      idempotencyKey: "key",
      routing: appFixtureRouting(),
      state: .uploading,
      uploadCheckpoint: UploadCheckpoint(
        resumptionToken: "private-token",
        chunkSizeBytes: 50,
        acknowledgedIndices: [0]
      )
    )

    continuation?.yield(UploadQueueStatus(entries: [entry]))
    for _ in 0..<10 {
      await Task.yield()
    }

    let title = menu.items.first { $0.tag == AgentMenu.uploadStatusItemTag }?.title ?? ""
    XCTAssertEqual(title, "Uploading 1 archive (50%)")
    XCTAssertFalse(title.contains("private-token"))
    XCTAssertFalse(title.contains(String(repeating: "e", count: 64)))
    withExtendedLifetime(binding) {}
  }

  @MainActor
  func testPausedUploadExposesBoundedRetryAndCancelActionsWithoutPrivateData() {
    let id = UUID()
    let entry = JournalEntry(
      id: id,
      fingerprint: ArchiveFingerprint(sha256Hex: String(repeating: "f", count: 64), byteSize: 1),
      idempotencyKey: "private-key",
      routing: appFixtureRouting(),
      state: .queued,
      uploadCheckpoint: UploadCheckpoint(
        resumptionToken: "private-token", chunkSizeBytes: 1, control: .paused
      )
    )
    let coordinator = AgentMenuCoordinator()
    let menu = AgentMenu.make(
      coordinator: coordinator, uploadStatus: UploadQueueStatus(entries: [entry])
    )

    let uploads = menu.items.first { $0.tag == AgentMenu.uploadControlsItemTag }
    let actions = uploads?.submenu?.items ?? []
    XCTAssertEqual(actions.map(\.title), ["Retry Now", "Cancel"])
    XCTAssertEqual(
      actions.map(\.action),
      [
        #selector(AgentMenuCoordinator.retryUploadSelected(_:)),
        #selector(AgentMenuCoordinator.cancelUploadSelected(_:)),
      ]
    )
    XCTAssertTrue(actions.allSatisfy { $0.target === coordinator })
    XCTAssertTrue(actions.allSatisfy { ($0.representedObject as? UUID) == id })
    let rendered = actions.map(\.title).joined()
    XCTAssertFalse(rendered.contains("private-token"))
    XCTAssertFalse(rendered.contains(String(repeating: "f", count: 64)))
  }
}
