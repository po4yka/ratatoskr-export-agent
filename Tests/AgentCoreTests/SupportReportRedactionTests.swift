import Foundation
import XCTest

@testable import AgentCore

final class SupportReportRedactionTests: XCTestCase {
  private let fullDigest = String(repeating: "ab", count: 32)

  func testDefaultReportExcludesSensitiveCanaries() throws {
    let item = try SupportReportItemSummary(entry: sensitiveEntry())
    let data = try SupportReportBuilder.make(
      snapshot: diagnosticSnapshot(),
      items: [item],
      failures: [],
      generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
      buildInfo: SupportReportBuildInfo(version: "0.1.0", build: "42")
    )
    let report = try XCTUnwrap(String(data: data, encoding: .utf8))

    XCTAssertTrue(report.contains("abababababab"))
    XCTAssertTrue(report.contains("queued"))
    XCTAssertFalse(report.contains(fullDigest))
    for canary in sensitiveCanaries {
      XCTAssertFalse(report.contains(canary), "default report leaked \(canary)")
    }
  }

  func testFreeFormFailureMapsToBoundedClassification() throws {
    let failure = SupportReportFailureSummary(
      classification: SupportReportFailureClassifier.classify(CanaryError()),
      count: 1
    )
    let data = try SupportReportBuilder.make(
      snapshot: diagnosticSnapshot(),
      items: [],
      failures: [failure],
      generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
      buildInfo: SupportReportBuildInfo(version: "0.1.0", build: "42")
    )
    let report = try XCTUnwrap(String(data: data, encoding: .utf8))

    XCTAssertTrue(report.contains("unknown"))
    XCTAssertFalse(report.contains(CanaryError().localizedDescription))
  }
}

extension SupportReportRedactionTests {
  func testExplicitSelectionIncludesOnlyOneReviewedField() throws {
    let item = try SupportReportItemSummary(entry: sensitiveEntry())
    let reviewed = SupportReportReviewedItemDetail(
      itemID: item.id,
      filename: "private-export.zip",
      textDetail: "PRIVATE_MESSAGE",
      url: "https://archive.invalid/report"
    )
    let selection = SupportReportDetailSelection(itemID: item.id, field: .filename)

    let report = try reportString(
      items: [item],
      reviewedDetails: [reviewed],
      selections: [selection]
    )

    XCTAssertTrue(report.contains("private-export.zip"))
    XCTAssertFalse(report.contains("PRIVATE_MESSAGE"))
    XCTAssertFalse(report.contains("https://archive.invalid/report"))
  }

  func testPathsAndCredentialsAreRefusedEvenWhenSelected() throws {
    let item = try SupportReportItemSummary(entry: sensitiveEntry())
    let pathDetail = SupportReportReviewedItemDetail(
      itemID: item.id,
      filename: "/Users/private/private-export.zip"
    )
    let credentialDetail = SupportReportReviewedItemDetail(
      itemID: item.id,
      url: credentialURL(path: "/report")
    )

    XCTAssertThrowsError(
      try reportString(
        items: [item],
        reviewedDetails: [pathDetail],
        selections: [.init(itemID: item.id, field: .filename)]
      )
    )
    XCTAssertThrowsError(
      try reportString(
        items: [item],
        reviewedDetails: [credentialDetail],
        selections: [.init(itemID: item.id, field: .url)]
      )
    )
  }

  func testExporterWritesExactlyPreviewedBytesLocally() throws {
    let writer = RecordingSupportReportWriter()
    let exporter = SupportReportExporter(writer: writer)
    let preview = Data("{\"safe\":true}".utf8)
    let destination = URL(fileURLWithPath: "/tmp/ratatoskr-support-report.json")

    try exporter.export(previewData: preview, to: destination)

    XCTAssertEqual(writer.writtenData, preview)
    XCTAssertEqual(writer.destination, destination)
  }

  private func reportString(
    items: [SupportReportItemSummary],
    reviewedDetails: [SupportReportReviewedItemDetail],
    selections: Set<SupportReportDetailSelection>
  ) throws -> String {
    let data = try SupportReportBuilder.make(
      snapshot: diagnosticSnapshot(),
      items: items,
      failures: [],
      generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
      buildInfo: SupportReportBuildInfo(version: "0.1.0", build: "42"),
      reviewedDetails: reviewedDetails,
      selections: selections
    )
    return try XCTUnwrap(String(data: data, encoding: .utf8))
  }

  private var sensitiveCanaries: [String] {
    [
      "private-export.zip",
      "/Users/private",
      "PRIVATE_MESSAGE",
      credentialURL(path: ""),
      "user:secret",
    ]
  }

  private func sensitiveEntry() -> JournalEntry {
    let fingerprint = ArchiveFingerprint(sha256Hex: fullDigest, byteSize: 2_048)
    return JournalEntry(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!,
      fingerprint: fingerprint,
      idempotencyKey: "ratatoskr-export-agent/sha256/\(fullDigest)",
      state: .queued,
      uploadCheckpoint: UploadCheckpoint(
        resumptionToken: credentialURL(path: "/private-export.zip?content=PRIVATE_MESSAGE"),
        chunkSizeBytes: 1_024,
        attemptCount: 3
      ),
      managedArchivePath: "/Users/private/private-export.zip"
    )
  }

  private func credentialURL(path: String) -> String {
    "https://user" + ":secret@archive.invalid" + path
  }

  private func diagnosticSnapshot() -> OperationalDiagnosticsSnapshot {
    OperationalDiagnosticsSnapshot(
      folderPermissions: .init(accessible: 1, needsReauthorization: 0, missing: 0, denied: 0),
      notifications: .authorized,
      diskSpace: .available(bytes: 8_388_608),
      journal: .healthy(entryCount: 1),
      queue: .available(.init(active: 0, queued: 1, paused: 0, retrying: 0, failed: 0)),
      updateCheck: .deferredPendingDistributionDecision
    )
  }
}

private struct CanaryError: LocalizedError {
  var errorDescription: String? {
    "PRIVATE_MESSAGE at /Users/private via https://user" + ":secret@archive.invalid"
  }
}

private final class RecordingSupportReportWriter: SupportReportWriting, @unchecked Sendable {
  private(set) var writtenData: Data?
  private(set) var destination: URL?

  func write(_ data: Data, to destination: URL) throws {
    writtenData = data
    self.destination = destination
  }
}
