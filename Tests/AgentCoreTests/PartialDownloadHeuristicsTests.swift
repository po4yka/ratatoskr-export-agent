import AgentCore
import XCTest

final class PartialDownloadHeuristicsTests: XCTestCase {
  func testKnownTemporarySuffixesAreRecognized() {
    for name in [
      "chatgpt-export.zip.download",
      "claude-archive.zip.crdownload",
      "export.zip.part",
      "export.zip.partial",
      "UPPER.ZIP.DOWNLOAD",
    ] {
      XCTAssertTrue(
        PartialDownloadHeuristics.hasTemporarySuffix(name),
        "\(name) carries a known temporary download suffix")
    }
  }

  func testCleanNamesAreNotFlagged() {
    for name in [
      "chatgpt-export.zip",
      "claude-archive.tar.gz",
      "notes.part2.zip",
      "my.download.folder.txt",
    ] {
      XCTAssertFalse(
        PartialDownloadHeuristics.hasTemporarySuffix(name),
        "\(name) has no temporary download suffix")
    }
  }
}
