import Foundation

/// A folder location produced by resolving stored bookmark bytes, carrying
/// whether the underlying folder appears to have moved since the bookmark
/// was created.
public struct ResolvedFolderLocation: Equatable, Sendable {
  /// The resolved directory URL.
  public var url: URL

  /// True when the system reports the bookmark as stale.
  public var isStale: Bool

  public init(url: URL, isStale: Bool) {
    self.url = url
    self.isStale = isStale
  }
}

/// Creates, resolves, and manages scoped access for security-scoped folder
/// bookmarks. All bookmark-system use funnels through here so sandbox
/// hardening changes exactly one implementation.
public protocol FolderBookmarkStoring: Sendable {
  /// Creates security-scoped bookmark bytes for a picked directory.
  func makeBookmarkData(for directoryURL: URL) throws -> Data

  /// Resolves bookmark bytes back to a folder location.
  func resolvedFolder(from bookmarkData: Data) throws -> ResolvedFolderLocation

  /// Begins scoped access for a resolved folder; returns whether the
  /// system granted a new scope.
  func startAccessing(_ resolved: ResolvedFolderLocation) -> Bool

  /// Ends scoped access previously begun for a resolved folder.
  func stopAccessing(_ resolved: ResolvedFolderLocation)

  /// Whether scoped access is currently held for the given URL.
  func hasActiveAccess(to url: URL) -> Bool
}

/// The production bookmark store wrapping the platform bookmark APIs.
public final class SecurityScopedBookmarkStore: FolderBookmarkStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var accessedURLs: Set<URL>

  public init() {
    accessedURLs = []
  }

  public func makeBookmarkData(for directoryURL: URL) throws -> Data {
    try directoryURL.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
  }

  public func resolvedFolder(from bookmarkData: Data) throws -> ResolvedFolderLocation {
    var stale = false
    let url = try URL(
      resolvingBookmarkData: bookmarkData,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &stale
    )
    return ResolvedFolderLocation(url: url, isStale: stale)
  }

  public func startAccessing(_ resolved: ResolvedFolderLocation) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let standardized = resolved.url.standardizedFileURL
    guard !accessedURLs.contains(standardized) else { return false }
    let granted = resolved.url.startAccessingSecurityScopedResource()
    if granted {
      accessedURLs.insert(standardized)
    }
    return granted
  }

  public func stopAccessing(_ resolved: ResolvedFolderLocation) {
    lock.lock()
    defer { lock.unlock() }
    let standardized = resolved.url.standardizedFileURL
    guard accessedURLs.remove(standardized) != nil else { return }
    resolved.url.stopAccessingSecurityScopedResource()
  }

  public func hasActiveAccess(to url: URL) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return accessedURLs.contains(url.standardizedFileURL)
  }
}
