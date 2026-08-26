import AgentCore
import XCTest

final class ArchiveClassifierSniffTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
      create: true
    )
  }

  override func tearDown() {
    if let directory {
      try? FileManager.default.removeItem(at: directory)
    }
  }

  func testZipMagicBytesAreRecognized() throws {
    let file = try writeClassifierFixture(
      named: "export.zip",
      bytes: makeZipData(entries: [ZipFixtureEntry(name: "anything.txt")]),
      into: directory
    )

    let classification = try ArchiveClassifier().classify(at: file)

    XCTAssertEqual(classification.container, .zip, "the PK signature must sniff as zip")
  }

  func testJsonShapeIsRecognizedAndPlainTextIsUnknown() throws {
    let jsonFile = try writeClassifierFixture(
      named: "export.json",
      bytes: Data("[{\"title\": \"x\"}]".utf8),
      into: directory
    )
    let textFile = try writeClassifierFixture(
      named: "notes.txt",
      bytes: Data("definitely not an archive".utf8),
      into: directory
    )

    let jsonClassification = try ArchiveClassifier().classify(at: jsonFile)
    let textClassification = try ArchiveClassifier().classify(at: textFile)

    XCTAssertEqual(jsonClassification.container, .json, "a JSON array prefix must sniff as json")
    XCTAssertEqual(
      textClassification.container, .unknown,
      "plain text matches no container signature")
  }
}
