import AgentCore
import XCTest

/// `device-results.json` names note paths, so only the owner reads it, and
/// a corrupt file is moved aside.
final class DeviceResultStoreTests: XCTestCase {
  private var root: URL!
  private var support: URL { root.appendingPathComponent("Support") }
  private var file: URL { support.appendingPathComponent("device-results.json") }

  override func setUpWithError() throws {
    root = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
      create: true
    )
  }

  override func tearDown() {
    if let root {
      try? FileManager.default.removeItem(at: root)
    }
  }

  func testTheFileIsReadableByTheOwnerOnly() async throws {
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
    let store = FileDeviceResultStore(fileURL: file)

    try await store.save(["o1": Data(#"{"outcome":"applied"}"#.utf8)], connectionID: "c1")

    XCTAssertEqual(try mode(of: file), 0o600, "the results name note paths")
    XCTAssertEqual(try mode(of: support), 0o700, "the support directory is the owner's only")
    let left = try FileManager.default.contentsOfDirectory(atPath: support.path)
    XCTAssertEqual(left, ["device-results.json"], "no temporary file is left")
  }

  func testACorruptFileIsMovedAsideAndTheStoreStartsEmpty() async throws {
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    try Data(#"{"connections":{"#.utf8).write(to: file)
    let lines = ResultLogLines()
    let store = FileDeviceResultStore(fileURL: file, now: { Date(timeIntervalSince1970: 1_800_000_000) }, log: { lines.append($0) })

    let loaded = try? await store.load(connectionID: "c1")
    try? await store.save(["o1": Data("r".utf8)], connectionID: "c1")
    let saved = try? await store.load(connectionID: "c1")

    let aside = support.appendingPathComponent("device-results.json.corrupt-1800000000")
    XCTAssertEqual(loaded, [:])
    XCTAssertEqual(try? String(contentsOf: aside, encoding: .utf8), #"{"connections":{"#, "the corrupt bytes are kept aside")
    XCTAssertEqual(saved, ["o1": Data("r".utf8)], "the store works again")
    XCTAssertEqual(lines.values.count, 1)
    XCTAssertTrue(lines.values.first?.contains("device-results.json.corrupt-1800000000") ?? false)
  }

  private func mode(of url: URL) throws -> Int {
    ((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777
  }
}

private final class ResultLogLines: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: [String] = []

  var values: [String] { lock.withLock { stored } }

  func append(_ line: String) {
    lock.withLock { stored.append(line) }
  }
}
