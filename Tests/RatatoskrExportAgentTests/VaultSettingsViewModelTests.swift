import AgentCore
import XCTest

@testable import RatatoskrExportAgent

@MainActor
final class VaultSettingsViewModelTests: XCTestCase {
  private var root: URL!

  override func setUp() async throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("ratatoskr-vaults-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Notes"), withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: root)
  }

  func testAddFromThePickerShowsTheVaultAndRemoveTakesItAway() throws {
    let registry = try WatchedVaultRegistry(
      store: FileWatchedVaultStore(fileURL: root.appendingPathComponent("vault-preferences.json")),
      bookmarkStore: SettingsVaultBookmarkStub(),
      vaultKey: { _ in "0f1e2d3c4b5a6978" },
      newKey: { "generated-key" }
    )
    var changes = 0
    let viewModel = VaultSettingsViewModel(
      registry: registry, picker: PickedFolder(url: root.appendingPathComponent("Notes")), onChange: { changes += 1 }
    )

    viewModel.addVaultFromPicker()
    let rows = viewModel.rows
    if let id = rows.first?.id {
      viewModel.remove(id: id)
    }

    XCTAssertEqual(rows.map(\.displayName), ["Notes"])
    XCTAssertEqual(viewModel.rows, [])
    XCTAssertEqual(registry.vaults, [])
    XCTAssertEqual(changes, 2)
  }
}

@MainActor
private struct PickedFolder: FolderPicking {
  let url: URL

  func pickFolder() -> URL? { url }
}

private final class SettingsVaultBookmarkStub: FolderBookmarkStoring, @unchecked Sendable {
  func makeBookmarkData(for directoryURL: URL) throws -> Data { Data("bookmark".utf8) }
  func resolvedFolder(from bookmarkData: Data) throws -> ResolvedFolderLocation {
    ResolvedFolderLocation(url: URL(fileURLWithPath: "/"), isStale: false)
  }
  func startAccessing(_ resolved: ResolvedFolderLocation) -> Bool { true }
  func stopAccessing(_ resolved: ResolvedFolderLocation) {}
  func hasActiveAccess(to url: URL) -> Bool { false }
}
