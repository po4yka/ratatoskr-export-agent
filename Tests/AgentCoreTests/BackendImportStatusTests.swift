import AgentCore
import Foundation
import XCTest

final class BackendImportStatusTests: XCTestCase {
  func testCompleteAndGapSummariesMapOnlyFromValidOperationPayloads() throws {
    XCTAssertEqual(
      try BackendImportStatusMapper.map(fixture(status: "succeeded", completeness: "complete")),
      .importedComplete
    )
    XCTAssertEqual(
      try BackendImportStatusMapper.map(fixture(status: "partially_succeeded", completeness: "assets_partial")),
      .importedWithGaps(gapCount: 2)
    )
  }

  func testFailedOperationDoesNotExposeBackendDiagnostic() throws {
    XCTAssertEqual(try BackendImportStatusMapper.map(failedFixture), .failed)
  }

  private func fixture(status: String, completeness: String) -> Data {
    Data("""
    {
      "operation_id":"00000000-0000-0000-0000-000000000001",
      "status":"\(status)",
      "results":[{
        "result_kind":"ai_archive.import",
        "target":"ai_archive:00000000-0000-0000-0000-000000000002",
        "ai_archive_import_summary":{
          "ai_archive_id":"00000000-0000-0000-0000-000000000002",
          "provider":"chatgpt",
          "completeness":"\(completeness)",
          "conversation_count":1,
          "message_count":2,
          "asset_count":3,
          "gap_count":\(completeness == "complete" ? 0 : 2),
          "warning_count":0
        }
      }]
    }
    """.utf8)
  }

  private let failedFixture = Data("""
  {
    "operation_id":"00000000-0000-0000-0000-000000000001",
    "status":"failed",
    "errors":[{"message":"private backend diagnostic"}]
  }
  """.utf8)
}
