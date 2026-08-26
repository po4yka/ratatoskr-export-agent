import AgentCore
import XCTest

final class LocalArchiveStoreBudgetTests: XCTestCase {
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
      maxStoreBytes: 1_000
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

  func testOverBudgetRefusalHappensBeforeAnyCopying() throws {
    let stored = Data(repeating: 0x11, count: 700)
    let first = try makeSource(named: "first.zip", bytes: stored)
    let preserved = try store.archive(
      sourceAt: first,
      observedByteSize: stored.count,
      classification: classification(provider: .chatgpt),
      archivedOn: Self.archivedOn
    )

    // 700 stored + 400 incoming exceeds the 1000-byte budget.
    let incoming = Data(repeating: 0x22, count: 400)
    let second = try makeSource(named: "second.zip", bytes: incoming)

    XCTAssertThrowsError(
      try store.archive(
        sourceAt: second,
        observedByteSize: incoming.count,
        classification: classification(provider: .claude),
        archivedOn: Self.archivedOn
      ),
      "projecting past the budget must refuse up front"
    ) { error in
      XCTAssertEqual(
        error as? LocalArchiveStoreError,
        .overBudget(currentBytes: 700, incomingBytes: 400, limitBytes: 1_000),
        "the refusal names current usage, the incoming size, and the limit")
    }
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: first.path),
      "refusal must not touch the user's original")
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: preserved.url.path),
      "refusal must not touch the previously preserved copy")
    XCTAssertEqual(
      try LocalArchiveStore.totalStoredBytes(under: store.root), 700,
      "the refused archive must add nothing to the store")
    let enumerator = FileManager.default.enumerator(at: store.root, includingPropertiesForKeys: nil)
    let names = (enumerator?.allObjects as? [URL])?.map(\.lastPathComponent) ?? []
    XCTAssertEqual(
      names.filter { $0.hasPrefix(LocalArchiveStore.temporaryPrefix) },
      [],
      "a refusal must never create a temporary copy")
  }

  func testWithinBudgetArchivalProceeds() throws {
    let stored = Data(repeating: 0x33, count: 600)
    let first = try makeSource(named: "first.zip", bytes: stored)
    _ = try store.archive(
      sourceAt: first,
      observedByteSize: stored.count,
      classification: classification(provider: .chatgpt),
      archivedOn: Self.archivedOn
    )

    let incoming = Data(repeating: 0x44, count: 300)
    let second = try makeSource(named: "second.zip", bytes: incoming)
    let record = try store.archive(
      sourceAt: second,
      observedByteSize: incoming.count,
      classification: classification(provider: .claude),
      archivedOn: Self.archivedOn
    )

    let totalAfter = try LocalArchiveStore.totalStoredBytes(under: store.root)
    XCTAssertEqual(
      totalAfter, 900,
      "within-budget archival grows the store by exactly the incoming size")
    XCTAssertEqual(record.fingerprint.byteSize, 300)
  }
}
