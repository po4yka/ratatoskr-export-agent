import Foundation

/// Orchestrates the watched-folder registry: the persisted preferences
/// document plus security-scoped bookmark lifecycle, exposed as one source
/// of truth for settings UI and (later) the watcher.
@MainActor
public final class WatchedFolderRegistry {
  private let preferencesStore: any FolderPreferencesStoring
  private let bookmarkStore: any FolderBookmarkStoring
  private var preferences: FolderPreferences

  public init(
    preferencesStore: any FolderPreferencesStoring,
    bookmarkStore: any FolderBookmarkStoring
  ) throws {
    self.preferencesStore = preferencesStore
    self.bookmarkStore = bookmarkStore
    preferences = try preferencesStore.load()
  }

  /// Registered folders in persistence order.
  public var folders: [WatchedFolderPreference] {
    preferences.folders
  }

  public func runtimeFolders() -> [(target: WatchedFolderTarget, policy: FolderArchivePolicy)] {
    preferences.folders.compactMap { folder in
      guard folder.isEnabled,
            let resolved = try? bookmarkStore.resolvedFolder(from: folder.bookmarkData),
            !resolved.isStale,
            FileManager.default.isReadableFile(atPath: resolved.url.path) else {
        return nil
      }
      _ = bookmarkStore.startAccessing(resolved)
      return (
        target: WatchedFolderTarget(id: folder.id, url: resolved.url, isEnabled: true),
        policy: folder.archivePolicy
      )
    }
  }

  /// Adds a picked folder, creating and persisting its bookmark entry.
  /// Adding a folder whose standardized path matches an existing entry
  /// returns that existing entry unchanged.
  @discardableResult
  public func addFolder(at url: URL) throws -> WatchedFolderPreference {
    let standardizedPath = url.standardizedFileURL.path
    if let existing = preferences.folders.first(where: { $0.displayPath == standardizedPath }) {
      return existing
    }
    let bookmarkData = try bookmarkStore.makeBookmarkData(for: url)
    let entry = WatchedFolderPreference(
      id: UUID(),
      displayPath: standardizedPath,
      bookmarkData: bookmarkData
    )
    var updated = preferences
    updated.folders.append(entry)
    try preferencesStore.save(updated)
    preferences = updated
    return entry
  }

  /// Removes a folder entry, relinquishing its scoped access.
  public func removeFolder(id: UUID) {
    guard let index = preferences.folders.firstIndex(where: { $0.id == id }) else { return }
    let entry = preferences.folders.remove(at: index)
    if let resolved = try? bookmarkStore.resolvedFolder(from: entry.bookmarkData) {
      bookmarkStore.stopAccessing(resolved)
    }
    try? preferencesStore.save(preferences)
  }

  /// Enables or disables watching for one folder.
  public func setEnabled(_ enabled: Bool, for id: UUID) throws {
    guard let index = preferences.folders.firstIndex(where: { $0.id == id }) else { return }
    preferences.folders[index].isEnabled = enabled
    try preferencesStore.save(preferences)
  }

  /// Sets the archive policy for one folder.
  public func setArchivePolicy(
    _ policy: FolderArchivePolicy, for id: UUID
  ) throws {
    guard let index = preferences.folders.firstIndex(where: { $0.id == id }) else { return }
    preferences.folders[index].archivePolicy = policy
    try preferencesStore.save(preferences)
  }

  /// Evaluates the current access state for one registered folder.
  public func accessState(for id: UUID) -> FolderAccessState {
    guard let entry = preferences.folders.first(where: { $0.id == id }) else {
      return .needsReauthorization
    }

    let resolved: ResolvedFolderLocation
    do {
      resolved = try bookmarkStore.resolvedFolder(from: entry.bookmarkData)
    } catch {
      return FolderAccessClassifier.state(for: .bookmarkUnresolvable)
    }
    if !FileManager.default.fileExists(atPath: resolved.url.path) {
      return FolderAccessClassifier.state(for: .targetVanished)
    }
    if resolved.isStale {
      return FolderAccessClassifier.state(for: .resolvedStale)
    }
    if !FileManager.default.isReadableFile(atPath: resolved.url.path) {
      return FolderAccessClassifier.state(for: .unreadableDueToPermissions)
    }
    return FolderAccessClassifier.state(for: .readable(resolved.url))
  }
}
