import Foundation

/// Archive policy applied to an accepted archive originating from a watched
/// folder: preserve it where it lies, or copy it into the local archive
/// layout after a successful upload.
public enum FolderArchivePolicy: String, Codable, Equatable, Sendable {
  case preserveInPlace
  case archiveAfterUpload
}

/// One registered watched folder: stable identity, sanitized display
/// metadata, per-folder settings, and the security-scoped bookmark bytes
/// that restore access across restarts.
public struct WatchedFolderPreference: Equatable, Sendable {
  /// Stable generated identity of this registry entry.
  public var id: UUID

  /// Display path shown to the user locally; never logged or transmitted.
  public var displayPath: String

  /// Whether the folder participates in watching.
  public var isEnabled: Bool

  /// What happens to accepted archives from this folder.
  public var archivePolicy: FolderArchivePolicy

  /// Security-scoped bookmark bytes resolving back to the folder.
  public var bookmarkData: Data

  public init(
    id: UUID,
    displayPath: String,
    isEnabled: Bool = true,
    archivePolicy: FolderArchivePolicy = .archiveAfterUpload,
    bookmarkData: Data
  ) {
    self.id = id
    self.displayPath = displayPath
    self.isEnabled = isEnabled
    self.archivePolicy = archivePolicy
    self.bookmarkData = bookmarkData
  }
}

/// The persisted watched-folder preferences document, schema version 1.
///
/// Loading applies documented defaults when the file does not exist and
/// rejects documents that deviate from the schema instead of guessing.
public struct FolderPreferences: Equatable, Sendable {
  /// Registered watched folders, in persistence order.
  public var folders: [WatchedFolderPreference]

  public init(folders: [WatchedFolderPreference] = []) {
    self.folders = folders
  }

  /// Loads the preferences document at the given file URL.
  ///
  /// A missing file yields an empty registry rather than an error, so a
  /// fresh installation starts with nothing watched. Present documents are
  /// decoded strictly: schema version 1 only, no unknown fields, no
  /// duplicate folder identities, no empty bookmark data.
  public static func load(from fileURL: URL) throws -> FolderPreferences {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return FolderPreferences()
    }
    let data = try Data(contentsOf: fileURL)
    let raw: FolderPreferencesDocument
    do {
      raw = try JSONDecoder().decode(FolderPreferencesDocument.self, from: data)
    } catch let rejection as FolderPreferencesRejection {
      throw FolderPreferencesLoadError(fileURL: fileURL, reason: rejection)
    }
    return FolderPreferences(folders: raw.folders.map(\.preference))
  }

  /// Saves the preferences document atomically to the given file URL.
  public func save(to fileURL: URL) throws {
    let raw = FolderPreferencesDocument(folders: folders.map(FolderPreferencesEntry.init))
    let data = try JSONEncoder().encode(raw)
    try data.write(to: fileURL, options: .atomic)
  }
}

/// Persists watched-folder preference documents. The file-backed store is
/// the production implementation; tests substitute recording stubs.
public protocol FolderPreferencesStoring: Sendable {
  /// Loads the current preferences document.
  func load() throws -> FolderPreferences

  /// Persists the given preferences document.
  func save(_ preferences: FolderPreferences) throws
}

/// File-backed preferences store using the document's atomic save.
public struct FileFolderPreferencesStore: FolderPreferencesStoring {
  private let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load() throws -> FolderPreferences {
    try FolderPreferences.load(from: fileURL)
  }

  public func save(_ preferences: FolderPreferences) throws {
    try preferences.save(to: fileURL)
  }
}
