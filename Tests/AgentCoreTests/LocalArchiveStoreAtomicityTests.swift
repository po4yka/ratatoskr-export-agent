import AgentCore
import CryptoKit
import XCTest

final class LocalArchiveStoreAtomicityTests: XCTestCase {
  private static let archivedOn = Date(timeIntervalSinceReferenceDate: 780_000_000)

  private var directory: URL!
  private var sourceDirectory: URL!
  private var store: LocalArchiveStore!

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
    store = LocalArchiveStore(
      root: base.appendingPathComponent("archive-store", isDirectory: true),
      maxStoreBytes: 10 * 1_048_576,
      hasher: StreamingHasher(chunkSize: 256)
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

  private func classification(provider: ArchiveProviderHint) -> ArchiveClassification {
    ArchiveClassification(
      container: .zip,
      provider: provider,
      confidence: .strong,
      matchedMarkers: []
    )
  }

  private func monthDirectory(provider: ArchiveProviderHint) -> URL {
    storeLayoutMonthDirectory(storeRoot: store.root, provider: provider, on: Self.archivedOn)
  }

  func testInterruptionMidCopyPublishesNothing() throws {
    let content = Data(repeating: 0x5A, count: 4_000)
    let source = try makeSource(named: "export.zip", bytes: content)

    XCTAssertThrowsError(
      try store.archive(
        sourceAt: source,
        observedByteSize: content.count,
        classification: classification(provider: .chatgpt),
        archivedOn: Self.archivedOn,
        publishHook: { checkpoint in
          // Two 256-byte chunks staged: terminate before the third flush.
          if checkpoint == .afterChunkFlush(512) {
            throw SimulatedTermination.error
          }
        }
      ),
      "an interrupted publication must surface the interruption"
    ) { error in
      XCTAssertEqual(error as? SimulatedTermination, SimulatedTermination.error)
    }

    let monthDirectory = self.monthDirectory(provider: .chatgpt)
    if FileManager.default.fileExists(atPath: monthDirectory.path) {
      let entries = try FileManager.default.contentsOfDirectory(atPath: monthDirectory.path)
      XCTAssertTrue(
        entries.isEmpty,
        "a simulated termination must leave no partial archive visible; found \(entries)")
    }
  }

  func testRetryAfterInterruptionSucceeds() throws {
    let content = Data("retry payload".utf8)
    let source = try makeSource(named: "export.zip", bytes: content)

    XCTAssertThrowsError(
      try store.archive(
        sourceAt: source,
        observedByteSize: content.count,
        classification: classification(provider: .claude),
        publishHook: { _ in throw SimulatedTermination.error }
      )
    )

    let record = try store.archive(
      sourceAt: source,
      observedByteSize: content.count,
      classification: classification(provider: .claude),
      archivedOn: Self.archivedOn
    )

    XCTAssertFalse(record.reusedExistingEntry)
    let stored = try StreamingHasher(chunkSize: 128).fingerprint(at: record.url)
    XCTAssertEqual(stored.byteSize, content.count, "the retry publishes fully verified bytes")
  }

  func testStaleTemporaryFilesAreSweptByTheNextRun() throws {
    let content = Data("sweep check".utf8)
    let source = try makeSource(named: "export.zip", bytes: content)
    let monthDirectory = self.monthDirectory(provider: .chatgpt)
    try FileManager.default.createDirectory(at: monthDirectory, withIntermediateDirectories: true)
    let staleTemp = monthDirectory.appending(path: ".ratatoskr-tmp-leftover")
    try Data("partial".utf8).write(to: staleTemp)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -7_200)],
      ofItemAtPath: staleTemp.path
    )

    _ = try store.archive(
      sourceAt: source,
      observedByteSize: content.count,
      classification: classification(provider: .chatgpt),
      archivedOn: Self.archivedOn
    )

    let entries = try FileManager.default.contentsOfDirectory(atPath: monthDirectory.path)
    XCTAssertEqual(
      entries.filter { $0.hasPrefix(".ratatoskr-tmp-") },
      [],
      "the next archival run sweeps temporaries abandoned by earlier terminations")
  }
}

/// Marks a simulated mid-copy termination in interruption tests.
enum SimulatedTermination: Error, Equatable {
  case error
}
