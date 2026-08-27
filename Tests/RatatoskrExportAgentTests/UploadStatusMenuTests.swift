import AgentCore
@testable import RatatoskrExportAgent
import XCTest

final class UploadStatusMenuTests: XCTestCase {
  @MainActor
  func testMenuShowsRedactedQueuedAndProgressState() {
    let entry = JournalEntry(
      id: UUID(),
      fingerprint: ArchiveFingerprint(sha256Hex: String(repeating: "d", count: 64), byteSize: 1),
      idempotencyKey: "key",
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
      state: .uploading,
      uploadCheckpoint: UploadCheckpoint(
        resumptionToken: "private-token",
        chunkSizeBytes: 50,
        acknowledgedIndices: [0]
      )
    )

    continuation?.yield(UploadQueueStatus(entries: [entry]))
    for _ in 0 ..< 10 {
      await Task.yield()
    }

    let title = menu.items.first { $0.tag == AgentMenu.uploadStatusItemTag }?.title ?? ""
    XCTAssertEqual(title, "Uploading 1 archive (50%)")
    XCTAssertFalse(title.contains("private-token"))
    XCTAssertFalse(title.contains(String(repeating: "e", count: 64)))
    withExtendedLifetime(binding) {}
  }
}
