import Foundation
import XCTest

@testable import AgentCore

final class OperationalDiagnosticsTests: XCTestCase {
  func testAssemblerPreservesMixedPermissionDiskJournalAndQueueState() {
    let snapshot = OperationalDiagnosticsAssembler.assemble(
      folderAccess: [
        .accessible(URL(fileURLWithPath: "/Users/private/inbox")),
        .needsReauthorization,
        .missing,
        .denied,
      ],
      notificationAuthorization: .deniedOrUnavailable,
      diskSpace: .available(bytes: 8_388_608),
      journalHealth: .healthy(entryCount: 1),
      queueStatus: UploadQueueStatus(entries: [queuedEntry()])
    )

    XCTAssertEqual(
      snapshot.folderPermissions,
      .init(accessible: 1, needsReauthorization: 1, missing: 1, denied: 1)
    )
    XCTAssertEqual(snapshot.notifications, .deniedOrUnavailable)
    XCTAssertEqual(snapshot.diskSpace, .available(bytes: 8_388_608))
    XCTAssertEqual(snapshot.journal, .healthy(entryCount: 1))
    XCTAssertEqual(
      snapshot.queue,
      .available(.init(active: 0, queued: 1, paused: 0, retrying: 0, failed: 0))
    )
  }

  func testCorruptJournalMakesQueueUnavailable() {
    let snapshot = OperationalDiagnosticsAssembler.assemble(
      folderAccess: [],
      notificationAuthorization: .authorized,
      diskSpace: .unavailable,
      journalHealth: .requiresAttention,
      queueStatus: UploadQueueStatus(entries: [queuedEntry()])
    )

    XCTAssertEqual(snapshot.journal, .requiresAttention)
    XCTAssertEqual(snapshot.queue, .unavailable)
  }

  func testUpdateCheckUsesManualDownloadWithoutGuessingVersion() {
    let snapshot = OperationalDiagnosticsAssembler.assemble(
      folderAccess: [],
      notificationAuthorization: .authorized,
      diskSpace: .unavailable,
      journalHealth: .unavailable,
      queueStatus: nil
    )

    XCTAssertEqual(
      String(describing: snapshot.updateCheck),
      "manualDownload(currentVersion: nil)"
    )
  }

  private func queuedEntry() -> JournalEntry {
    let fingerprint = ArchiveFingerprint(
      sha256Hex: String(repeating: "a", count: 64),
      byteSize: 1_024
    )
    return JournalEntry(
      id: UUID(),
      fingerprint: fingerprint,
      idempotencyKey: "ratatoskr-export-agent/sha256/\(fingerprint.sha256Hex)",
      state: .queued
    )
  }
}
