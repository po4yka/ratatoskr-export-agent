import AgentCore
import XCTest

@MainActor
final class WatchedFolderRegistryTests: XCTestCase {
  private let pickedURL = URL(fileURLWithPath: "/Users/somebody/Ratatoskr Inbox")
  private let stubBookmark = Data("stub-security-scoped-bookmark".utf8)

  private var entryID: UUID {
    UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
  }

  func testFailedSaveLeavesRegistryUnchanged() throws {
    let preferences = ThrowingPreferencesStore()
    let registry = try WatchedFolderRegistry(
      preferencesStore: preferences, bookmarkStore: StubBookmarkStore(bookmarkData: stubBookmark))

    XCTAssertThrowsError(try registry.addFolder(at: pickedURL)) { _ in
      // the failure must propagate to the caller
    }

    XCTAssertTrue(
      registry.folders.isEmpty,
      "a failed save must leave the in-memory registry unchanged")
  }

  private func makeRegistry(
    bookmarks: StubBookmarkStore? = nil
  ) throws -> WatchedFolderRegistry {
    try WatchedFolderRegistry(
      preferencesStore: RecordingPreferencesStore(),
      bookmarkStore: bookmarks ?? StubBookmarkStore(bookmarkData: stubBookmark))
  }

  func testAddCreatesPersistedEntryWithCreatedBookmark() throws {
    let preferences = RecordingPreferencesStore()
    let bookmarks = StubBookmarkStore(bookmarkData: stubBookmark)
    let registry = try WatchedFolderRegistry(
      preferencesStore: preferences, bookmarkStore: bookmarks)

    let entry = try registry.addFolder(at: pickedURL)

    XCTAssertEqual(registry.folders.count, 1, "the picked folder must be registered")
    XCTAssertEqual(entry.displayPath, pickedURL.path)
    XCTAssertEqual(entry.bookmarkData, stubBookmark, "entry must carry the created bookmark")
    XCTAssertEqual(entry.isEnabled, true, "a new folder starts enabled")
    XCTAssertEqual(entry.archivePolicy, .archiveAfterUpload, "default policy applies")
    XCTAssertEqual(
      preferences.savedDocuments.last?.folders, [entry],
      "the entry must be persisted before add returns")
  }

  func testAddingSameFolderTwiceYieldsOneEntry() throws {
    let registry = try makeRegistry()

    _ = try registry.addFolder(at: pickedURL)
    _ = try registry.addFolder(at: pickedURL)

    XCTAssertEqual(
      registry.folders.count, 1,
      "adding the same folder twice must not duplicate the entry")
  }

  func testRemoveDropsEntryAndReleasesAccess() throws {
    let bookmarks = StubBookmarkStore(bookmarkData: stubBookmark)
    let registry = try makeRegistry(bookmarks: bookmarks)
    _ = try registry.addFolder(at: pickedURL)

    registry.removeFolder(id: registry.folders.first!.id)

    XCTAssertTrue(registry.folders.isEmpty, "removal must drop the entry")
    XCTAssertNotNil(
      bookmarks.stoppedAccessingLast,
      "removal must relinquish any held scoped access")
  }

  func testUnresolvableFolderStaysListedAsNeedsReauthorization() throws {
    let bookmarks = StubBookmarkStore(bookmarkData: stubBookmark)
    bookmarks.resolveError = StubError()
    let registry = try makeRegistry(bookmarks: bookmarks)
    _ = try registry.addFolder(at: pickedURL)

    let state = registry.accessState(for: registry.folders.first!.id)

    XCTAssertEqual(
      state, .needsReauthorization,
      "an unresolvable bookmark must surface as needs-reauthorization")
    XCTAssertEqual(
      registry.folders.count, 1,
      "a broken bookmark must not remove the folder from the registry")
  }
}

private struct StubError: Error {}

private final class ThrowingPreferencesStore: FolderPreferencesStoring, @unchecked Sendable {
  func load() throws -> FolderPreferences {
    FolderPreferences()
  }

  func save(_ preferences: FolderPreferences) throws {
    throw StubError()
  }
}

private final class RecordingPreferencesStore: FolderPreferencesStoring, @unchecked Sendable {
  private(set) var savedDocuments: [FolderPreferences] = []
  private var current = FolderPreferences()

  func load() throws -> FolderPreferences {
    current
  }

  func save(_ preferences: FolderPreferences) throws {
    savedDocuments.append(preferences)
    current = preferences
  }
}

private final class StubBookmarkStore: FolderBookmarkStoring, @unchecked Sendable {
  let bookmarkData: Data
  var resolveError: (any Error)?
  private(set) var stoppedAccessingLast: ResolvedFolderLocation?

  init(bookmarkData: Data) {
    self.bookmarkData = bookmarkData
  }

  func makeBookmarkData(for directoryURL: URL) throws -> Data {
    bookmarkData
  }

  func resolvedFolder(from bookmarkData: Data) throws -> ResolvedFolderLocation {
    if let resolveError {
      throw resolveError
    }
    return ResolvedFolderLocation(url: directoryURLForStub, isStale: false)
  }

  private var directoryURLForStub: URL {
    URL(fileURLWithPath: "/Users/somebody/Ratatoskr Inbox")
  }

  func startAccessing(_ resolved: ResolvedFolderLocation) -> Bool {
    true
  }

  func stopAccessing(_ resolved: ResolvedFolderLocation) {
    stoppedAccessingLast = resolved
  }

  func hasActiveAccess(to url: URL) -> Bool {
    false
  }
}
