import AgentCore
import CryptoKit
import XCTest

/// Occupied-path integrity: foreign content at a digest address is refused,
/// never displaced.
final class LocalArchiveStoreIntegrityTests: XCTestCase {
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
    let file = sourceDirectory.appendingPathComponent(name)
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

  func testMismatchedContentAtOccupiedPathFailsExplicitly() throws {
    let content = Data("true content".utf8)
    let source = try makeSource(named: "export.zip", bytes: content)
    _ = try store.archive(
      sourceAt: source,
      observedByteSize: content.count,
      classification: classification(provider: .chatgpt),
      archivedOn: Self.archivedOn
    )

    // Plant different bytes exactly where the impostor's digest would land.
    let impostor = try plantForeignContent(forPayload: Data("impostor payload".utf8))

    let impostorSource = try makeSource(named: "impostor.zip", bytes: impostor.content)
    XCTAssertThrowsError(
      try store.archive(
        sourceAt: impostorSource,
        observedByteSize: impostor.content.count,
        classification: classification(provider: .chatgpt),
        archivedOn: Self.archivedOn
      ),
      "different content at an occupied digest path must fail explicitly"
    ) { error in
      XCTAssertEqual(
        error as? LocalArchiveStoreError,
        .occupiedDigestMismatch(digestPrefix: String(impostor.digest.prefix(12)))
      )
    }
    XCTAssertEqual(
      try Data(contentsOf: impostor.path), impostor.plantedBytes,
      "the occupying file must remain byte-for-byte unchanged")
  }

  /// Foreign bytes planted at the digest-addressed path of a not-yet-
  /// archived payload, so publication hits an occupied path.
  private struct PlantedImpostor {
    let content: Data
    let digest: String
    let path: URL
    let plantedBytes: Data
  }

  /// Writes foreign bytes at the digest-addressed path of a not-yet-archived
  /// payload.
  private func plantForeignContent(forPayload payload: Data) throws -> PlantedImpostor {
    let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    let path = monthDirectory(provider: .chatgpt).appending(path: "\(digest).zip")
    try FileManager.default.createDirectory(
      at: path.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    let plantedBytes = Data("planted different bytes".utf8)
    try plantedBytes.write(to: path)
    return PlantedImpostor(
      content: payload, digest: digest, path: path, plantedBytes: plantedBytes
    )
  }
}
