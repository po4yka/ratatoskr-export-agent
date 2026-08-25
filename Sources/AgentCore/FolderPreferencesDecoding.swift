import Foundation

/// Strict persistence decoding for the watched-folder preferences document.
///
/// Mirrors the typed-configuration conventions: the schema-version gate runs
/// before anything else, the key set is compared against known fields, and
/// per-entry rules reject duplicate identities and empty bookmark data,
/// naming the offender.
struct FolderPreferencesLoadError: Error, CustomStringConvertible, Sendable {
  let fileURL: URL
  let reason: FolderPreferencesRejection

  var description: String {
    "\(fileURL.path): \(reason)"
  }
}

enum FolderPreferencesRejection: Error, CustomStringConvertible {
  case unsupportedSchemaVersion(Int?)
  case unknownField(String)
  case duplicatedFolderID(String)
  case emptyBookmarkData(entryID: String)

  var description: String {
    switch self {
    case .unsupportedSchemaVersion(.some(let actual)):
      "only schema version 1 is supported, found \(actual)"
    case .unsupportedSchemaVersion(.none):
      "only schema version 1 is supported, none declared"
    case .unknownField(let name):
      "unknown preferences field \"\(name)\""
    case .duplicatedFolderID(let id):
      "duplicated folder ID \(id)"
    case .emptyBookmarkData(let id):
      "folder entry \(id) carries empty bookmark data"
    }
  }
}

/// Persistence shape of the preferences document.
struct FolderPreferencesDocument: Codable {
  var folders: [FolderPreferencesEntry]

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case folders
  }

  init(folders: [FolderPreferencesEntry]) {
    self.folders = folders
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let declaredVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
    guard declaredVersion == 1 else {
      throw FolderPreferencesRejection.unsupportedSchemaVersion(declaredVersion)
    }
    let rawContainer = try decoder.container(keyedBy: AnyCodingKey.self)
    let knownFieldNames: Set<String> = [
      CodingKeys.schemaVersion.stringValue,
      CodingKeys.folders.stringValue,
    ]
    if let unexpected = rawContainer.allKeys.first(where: {
      !knownFieldNames.contains($0.stringValue)
    }) {
      throw FolderPreferencesRejection.unknownField(unexpected.stringValue)
    }
    folders = try container.decode([FolderPreferencesEntry].self, forKey: .folders)
    var seenIDs = Set<String>()
    for entry in folders {
      guard seenIDs.insert(entry.id.uuidString).inserted else {
        throw FolderPreferencesRejection.duplicatedFolderID(entry.id.uuidString)
      }
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(1, forKey: .schemaVersion)
    try container.encode(folders, forKey: .folders)
  }
}

/// Persistence shape of one registry entry.
struct FolderPreferencesEntry: Codable {
  var id: UUID
  var displayPath: String
  var enabled: Bool
  var archivePolicy: FolderArchivePolicy
  var bookmarkDataBase64: Data

  private enum CodingKeys: String, CodingKey {
    case id
    case displayPath
    case enabled
    case archivePolicy
    case bookmarkDataBase64
  }

  init(preference: WatchedFolderPreference) {
    id = preference.id
    displayPath = preference.displayPath
    enabled = preference.isEnabled
    archivePolicy = preference.archivePolicy
    bookmarkDataBase64 = preference.bookmarkData
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    displayPath = try container.decode(String.self, forKey: .displayPath)
    enabled = try container.decode(Bool.self, forKey: .enabled)
    archivePolicy = try container.decode(FolderArchivePolicy.self, forKey: .archivePolicy)
    bookmarkDataBase64 = try container.decode(Data.self, forKey: .bookmarkDataBase64)
    if bookmarkDataBase64.isEmpty {
      throw FolderPreferencesRejection.emptyBookmarkData(entryID: id.uuidString)
    }
  }

  var preference: WatchedFolderPreference {
    WatchedFolderPreference(
      id: id,
      displayPath: displayPath,
      isEnabled: enabled,
      archivePolicy: archivePolicy,
      bookmarkData: bookmarkDataBase64
    )
  }
}

private struct AnyCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int?

  init?(stringValue: String) {
    self.stringValue = stringValue
    intValue = nil
  }

  init?(intValue: Int) {
    stringValue = String(intValue)
    self.intValue = intValue
  }
}
