import AgentCore
import XCTest

@testable import RatatoskrExportAgent

@MainActor
final class FolderSettingsViewModelTests: XCTestCase {
  private var watchedDirectory: URL!

  override func setUp() async throws {
    watchedDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ratatoskr-settings-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: watchedDirectory, withIntermediateDirectories: true)
  }

  private func makePopulatedRegistry() throws -> (WatchedFolderRegistry, UUID) {
    let registry = try WatchedFolderRegistry(
      preferencesStore: MemoryPreferencesStore(),
      bookmarkStore: StubBookmarkStore(resolvedURL: watchedDirectory))
    let entry = try registry.addFolder(at: watchedDirectory)
    return (registry, entry.id)
  }

  func testRowsMirrorRegistryEntries() throws {
    let (registry, _) = try makePopulatedRegistry()

    let viewModel = FolderSettingsViewModel(registry: registry)

    XCTAssertEqual(viewModel.rows.count, registry.folders.count)
    XCTAssertEqual(viewModel.rows.first?.displayPath, watchedDirectory.path)
    XCTAssertEqual(viewModel.rows.first?.isEnabled, true)
    XCTAssertEqual(viewModel.rows.first?.archivePolicy, .archiveAfterUpload)
    XCTAssertEqual(
      viewModel.rows.first?.accessState, .accessible(watchedDirectory),
      "rows must carry the registry's evaluated access state")
  }

  func testToggleDisablesEntryAndPersists() throws {
    let (registry, id) = try makePopulatedRegistry()
    let viewModel = FolderSettingsViewModel(registry: registry)

    viewModel.setEnabled(false, id: id)

    XCTAssertEqual(viewModel.rows.first?.isEnabled, false, "the row must reflect the toggle")
    XCTAssertEqual(
      registry.folders.first?.isEnabled, false,
      "the toggle must persist through the registry")
  }

  func testPolicyChangePersists() throws {
    let (registry, id) = try makePopulatedRegistry()
    let viewModel = FolderSettingsViewModel(registry: registry)

    viewModel.setArchivePolicy(.preserveInPlace, id: id)

    XCTAssertEqual(
      viewModel.rows.first?.archivePolicy, .preserveInPlace,
      "the row must reflect the policy change")
    XCTAssertEqual(
      registry.folders.first?.archivePolicy, .preserveInPlace,
      "the policy change must persist through the registry")
  }
}

private struct StubError: Error {}

private final class MemoryPreferencesStore: FolderPreferencesStoring, @unchecked Sendable {
  private var current = FolderPreferences()

  func load() throws -> FolderPreferences {
    current
  }

  func save(_ preferences: FolderPreferences) throws {
    current = preferences
  }
}

private final class StubBookmarkStore: FolderBookmarkStoring, @unchecked Sendable {
  private let resolvedURL: URL

  init(resolvedURL: URL) {
    self.resolvedURL = resolvedURL
  }

  func makeBookmarkData(for directoryURL: URL) throws -> Data {
    Data("stub-bookmark".utf8)
  }

  func resolvedFolder(from bookmarkData: Data) throws -> ResolvedFolderLocation {
    ResolvedFolderLocation(url: resolvedURL, isStale: false)
  }

  func startAccessing(_ resolved: ResolvedFolderLocation) -> Bool {
    true
  }

  func stopAccessing(_ resolved: ResolvedFolderLocation) {}

  func hasActiveAccess(to url: URL) -> Bool {
    false
  }
}
