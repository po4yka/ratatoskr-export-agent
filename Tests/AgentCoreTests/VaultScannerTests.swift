import AgentCore
import XCTest

final class VaultScannerTests: XCTestCase {
  private var vault: URL!

  override func setUpWithError() throws {
    vault = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
      create: true
    )
  }

  override func tearDown() {
    if let vault {
      try? FileManager.default.removeItem(at: vault)
    }
  }

  func testRescanIndexesVisibleFilesOnly() throws {
    try write("Notes/A.md", "alpha")
    try write(".obsidian/workspace.json", "{}")
    try write("Notes/.DS_Store", "x")
    var scanner = VaultScanner(root: vault)

    let observations = scanner.rescan()

    XCTAssertEqual(observations.map(\.path), ["Notes/A.md"])
    XCTAssertEqual(Array(scanner.index.keys), ["Notes/A.md"])
  }

  func testEditAndDeleteAreObserved() throws {
    try write("A.md", "one")
    var scanner = VaultScanner(root: vault)
    _ = scanner.rescan()

    try write("A.md", "two")
    let edited = scanner.scan(paths: [path("A.md")])
    try FileManager.default.removeItem(at: vault.appendingPathComponent("A.md"))
    let removed = scanner.scan(paths: [path("A.md")])

    XCTAssertEqual(edited.map(\.isModified), [true])
    XCTAssertEqual(removed, [.deleted(path: "A.md", sha256: edited.first?.sha256 ?? "")])
  }

  func testFolderRenameIsOneRenamedChangePerFile() throws {
    try write("Old/A.md", "alpha")
    try write("Old/Sub/B.md", "beta")
    var scanner = VaultScanner(root: vault)
    _ = scanner.rescan()
    try FileManager.default.moveItem(at: vault.appendingPathComponent("Old"), to: vault.appendingPathComponent("New"))
    var watcher = VaultWatcher(firstSequence: 1)
    let now = Date(timeIntervalSinceReferenceDate: 0)

    for observation in scanner.scan(paths: [path("New"), path("Old")]) {
      watcher.record(observation, at: now)
    }
    let changes = watcher.drain(at: now.addingTimeInterval(5))

    XCTAssertEqual(changes.map(\.kind), [.renamed, .renamed])
    XCTAssertEqual(changes.map(\.path), ["New/A.md", "New/Sub/B.md"])
    XCTAssertEqual(changes.map(\.previousPath), ["Old/A.md", "Old/Sub/B.md"])
  }

  func testNFDNameOnDiskIsReportedAsNFC() throws {
    let decomposed = "Cafe\u{0301}.md"
    try write(decomposed, "menu")
    var scanner = VaultScanner(root: vault)

    let paths = scanner.rescan().map(\.path)

    XCTAssertEqual(paths.map { Array($0.unicodeScalars) }, [Array("Caf\u{00E9}.md".unicodeScalars)])
  }

  func testFileOverTheSizeLimitIsNotIndexed() throws {
    try write("Big.bin", String(repeating: "x", count: 11))
    var scanner = VaultScanner(root: vault, maximumByteLength: 10)

    XCTAssertEqual(scanner.rescan(), [])
  }

  private func path(_ relative: String) -> String {
    vault.appendingPathComponent(relative).path
  }

  private func write(_ relative: String, _ text: String) throws {
    let url = vault.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
  }
}

extension VaultObservation {
  var isModified: Bool {
    if case .modified = self {
      return true
    }
    return false
  }
}
