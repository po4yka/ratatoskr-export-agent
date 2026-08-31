import AgentCore
import XCTest

final class PlatformArchiveOperationQueueTests: XCTestCase {
  func testTransferFailureRetainsBoundOperationForPolling() async throws {
    let (journal, entry) = try operationEntry(named: "operation-upload-failure")
    let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000112")!
    let queue = UploadQueue(journal: journal,
      operationTransport: FailingTransferTransport(operationID: operationID), configuration: .defaultValue)
    _ = await queue.runEligible(now: Date(timeIntervalSince1970: 1))
    let entries = await queue.entries()
    let retained = entries.first(where: { $0.id == entry.id })
    XCTAssertEqual(retained?.operationID, operationID)
    XCTAssertEqual(retained?.state, .queued)
  }

  func testOperationQueueBindsPlatformOperationBeforeItMarksUploadCompleted() async throws {
    let (journal, entry) = try operationEntry(named: "operation-queue")
    let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000113")!
    let transport = BindingAwareTransport(journal: journal, entryID: entry.id, operationID: operationID)
    let queue = UploadQueue(journal: journal,
      operationTransport: transport, configuration: .defaultValue)
    _ = await queue.runEligible(now: Date(timeIntervalSince1970: 1))
    let entries = await queue.entries()
    let completed = try XCTUnwrap(entries.first)
    XCTAssertEqual(completed.state, .uploaded)
    XCTAssertEqual(completed.operationID, operationID)
    XCTAssertEqual(transport.events, ["prepare", "transfer"])
  }
}
