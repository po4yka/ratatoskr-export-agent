import AgentCore
import XCTest

final class FolderPreferencesDocumentTests: XCTestCase {
  private func temporaryPreferencesURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "ratatoskr-preferences-\(UUID().uuidString).json")
  }

  private func syntheticBookmarkData() -> Data {
    Data("synthetic-security-scoped-bookmark".utf8)
  }

  private func sampleEntry(
    id: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
    displayPath: String = "/Users/somebody/Ratatoskr Inbox"
  ) -> WatchedFolderPreference {
    WatchedFolderPreference(
      id: id,
      displayPath: displayPath,
      bookmarkData: syntheticBookmarkData()
    )
  }

  func testMissingFileYieldsEmptyRegistry() throws {
    let preferences = try FolderPreferences.load(from: temporaryPreferencesURL())

    XCTAssertTrue(
      preferences.folders.isEmpty,
      "a missing preferences file must yield an empty registry"
    )
  }

  func testSavedEntriesSurviveReload() throws {
    let url = temporaryPreferencesURL()
    let entry = sampleEntry()
    let preferences = FolderPreferences(folders: [entry])

    try preferences.save(to: url)
    let reloaded = try FolderPreferences.load(from: url)

    XCTAssertEqual(reloaded.folders, [entry], "saved entries must survive a reload unchanged")
  }

  func testDisabledFlagSurvivesReload() throws {
    let url = temporaryPreferencesURL()
    let disabled = WatchedFolderPreference(
      id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
      displayPath: "/Users/somebody/Ratatoskr Inbox",
      isEnabled: false,
      archivePolicy: .archiveAfterUpload,
      bookmarkData: syntheticBookmarkData()
    )
    let preferences = FolderPreferences(folders: [disabled])

    try preferences.save(to: url)
    let reloaded = try FolderPreferences.load(from: url)

    XCTAssertEqual(
      reloaded.folders.first?.isEnabled, false, "the disabled flag must survive a reload")
  }

  func testPreserveInPlacePolicySurvivesReload() throws {
    let url = temporaryPreferencesURL()
    let preserving = WatchedFolderPreference(
      id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
      displayPath: "/Users/somebody/Ratatoskr Inbox",
      isEnabled: true,
      archivePolicy: .preserveInPlace,
      bookmarkData: syntheticBookmarkData()
    )
    let preferences = FolderPreferences(folders: [preserving])

    try preferences.save(to: url)
    let reloaded = try FolderPreferences.load(from: url)

    XCTAssertEqual(
      reloaded.folders.first?.archivePolicy, .preserveInPlace,
      "the preserve-in-place policy must survive a reload")
  }
}
