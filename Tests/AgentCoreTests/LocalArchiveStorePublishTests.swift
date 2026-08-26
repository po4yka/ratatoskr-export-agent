import AgentCore
import CryptoKit
import XCTest

final class LocalArchiveStorePublishTests: XCTestCase {
  private var directory: URL!
  private var sourceDirectory: URL!

  override func setUpWithError() throws {
    let base = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
      create: true
    )
    directory = base
    sourceDirectory = base.appendingPathComponent("inbox", isDirectory: true)
    try FileManager.default.createDirectory(
      at: sourceDirectory, withIntermediateDirectories: true
    )
  }

  override func tearDown() {
    if let directory {
      try? FileManager.default.removeItem(at: directory)
    }
  }

  private func makeSource(named name: String, bytes: Data) throws -> URL {
    let file = sourceDirectory.appending(path: name)
    try bytes.write(to: file, options: .atomic)
    return file
  }

  private func makeStore(limitBytes: Int) -> LocalArchiveStore {
    LocalArchiveStore(
      root: directory.appendingPathComponent("archive-store", isDirectory: true),
      maxStoreBytes: limitBytes
    )
  }

  private func classification(provider: ArchiveProviderHint) -> ArchiveClassification {
    ArchiveClassification(
      container: .zip,
      provider: provider,
      confidence: .strong,
      matchedMarkers: []
    )
  }

  private static let archivedOn = Date(timeIntervalSinceReferenceDate: 780_000_000)

  func testArchivingPublishesVerifiedDigestAddressedCopy() throws {
    let content = Data((0..<2_500).map { UInt8(truncatingIfNeeded: $0 &* 13 &+ 5) })
    let source = try makeSource(named: "export.zip", bytes: content)
    let store = makeStore(limitBytes: 10 * 1_048_576)

    let record = try store.archive(
      sourceAt: source,
      observedByteSize: content.count,
      classification: classification(provider: .chatgpt),
      archivedOn: Self.archivedOn
    )

    XCTAssertEqual(record.providerSegment, "chatgpt")
    XCTAssertFalse(record.reusedExistingEntry, "a fresh publication is not a reuse")
    XCTAssertTrue(FileManager.default.fileExists(atPath: record.url.path))
    XCTAssertEqual(
      record.url.lastPathComponent,
      "\(record.fingerprint.sha256Hex).zip",
      "the final name must be the digest plus the container extension")
    XCTAssertTrue(
      record.url.standardizedFileURL.path.contains("/chatgpt/"),
      "the record lives under its provider segment")
    let storedFingerprint = try StreamingHasher(chunkSize: 256).fingerprint(at: record.url)
    XCTAssertEqual(storedFingerprint.sha256Hex, record.fingerprint.sha256Hex)
    XCTAssertEqual(storedFingerprint.byteSize, content.count)
    let expectedDigest = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
    XCTAssertEqual(record.fingerprint.sha256Hex, expectedDigest)
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: source.path),
      "archiving must never remove the user's original")
  }

  func testDuplicateArchivalReusesStoredEntryWithoutRewrite() throws {
    let content = Data("identical export payload".utf8)
    let source = try makeSource(named: "export.zip", bytes: content)
    let store = makeStore(limitBytes: 10 * 1_048_576)

    let first = try store.archive(
      sourceAt: source,
      observedByteSize: content.count,
      classification: classification(provider: .claude),
      archivedOn: Self.archivedOn
    )
    let attributesBefore = try FileManager.default.attributesOfItem(atPath: first.url.path)
    let inodeBefore = (attributesBefore[.systemFileNumber] as? NSNumber)?.int64Value

    let second = try store.archive(
      sourceAt: source,
      observedByteSize: content.count,
      classification: classification(provider: .claude),
      archivedOn: Self.archivedOn.addingTimeInterval(60)
    )

    XCTAssertTrue(second.reusedExistingEntry, "the same digest must reuse the stored entry")
    XCTAssertEqual(second.url, first.url)
    let attributesAfter = try FileManager.default.attributesOfItem(atPath: first.url.path)
    XCTAssertEqual(
      (attributesAfter[.modificationDate] as? Date),
      (attributesBefore[.modificationDate] as? Date),
      "a reused entry keeps its original modification time")
    XCTAssertEqual(
      (attributesAfter[.systemFileNumber] as? NSNumber)?.int64Value,
      inodeBefore,
      "a reused entry is never rewritten")
    let leftovers = try FileManager.default.contentsOfDirectory(
      atPath: second.url.deletingLastPathComponent().path)
    XCTAssertTrue(
      leftovers.allSatisfy { !$0.hasPrefix(".ratatoskr-tmp-") },
      "no temporary files may remain after archival")
  }
}
