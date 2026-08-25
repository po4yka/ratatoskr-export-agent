import AgentCore
import XCTest

final class FolderBookmarkStoreTests: XCTestCase {
  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ratatoskr-bookmark-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  func testBookmarkRoundTripResolvesSameDirectory() throws {
    let pickedDirectory = try makeTemporaryDirectory()
    let probeFile = pickedDirectory.appendingPathComponent("probe.txt")
    try Data("probe".utf8).write(to: probeFile)
    let store = SecurityScopedBookmarkStore()

    let bookmarkData = try store.makeBookmarkData(for: pickedDirectory)
    let resolved = try store.resolvedFolder(from: bookmarkData)

    XCTAssertEqual(
      resolved.url.standardizedFileURL, pickedDirectory.standardizedFileURL,
      "resolving the bookmark must yield the picked directory itself")
    let probeContents = try String(
      contentsOf: resolved.url.appendingPathComponent("probe.txt"), encoding: .utf8)
    XCTAssertEqual(
      probeContents, "probe",
      "the resolved folder's contents must be readable")
  }

  func testFreshInstanceResolvesStoredBytes() throws {
    let pickedDirectory = try makeTemporaryDirectory()
    let creatingStore = SecurityScopedBookmarkStore()

    let bookmarkData = try creatingStore.makeBookmarkData(for: pickedDirectory)

    let freshStore = SecurityScopedBookmarkStore()
    let resolved = try freshStore.resolvedFolder(from: bookmarkData)

    XCTAssertEqual(
      resolved.url.standardizedFileURL, pickedDirectory.standardizedFileURL,
      "a fresh store instance must resolve stored bytes without the picking session")
  }

  func testReleaseDropsHeldAccess() throws {
    let pickedDirectory = try makeTemporaryDirectory()
    let store = SecurityScopedBookmarkStore()
    let bookmarkData = try store.makeBookmarkData(for: pickedDirectory)
    let resolved = try store.resolvedFolder(from: bookmarkData)

    store.startAccessing(resolved)
    XCTAssertTrue(
      store.hasActiveAccess(to: resolved.url),
      "access must be held while scoped access is active")

    store.stopAccessing(resolved)
    XCTAssertFalse(
      store.hasActiveAccess(to: resolved.url),
      "no access may remain held after releasing")
  }
}
