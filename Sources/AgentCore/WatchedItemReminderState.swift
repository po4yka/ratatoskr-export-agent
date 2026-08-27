import Foundation

public struct WatchedFolderReminderState: Codable, Equatable, Sendable {
  public let folderID: UUID
  public let deliveredForCurrentCondition: Bool
  public let snoozedUntil: Date?

  public init(
    folderID: UUID,
    deliveredForCurrentCondition: Bool,
    snoozedUntil: Date?
  ) {
    self.folderID = folderID
    self.deliveredForCurrentCondition = deliveredForCurrentCondition
    self.snoozedUntil = snoozedUntil
  }
}

public struct WatchedItemReminderStateDocument: Codable, Equatable, Sendable {
  public let folders: [WatchedFolderReminderState]
  public let lastEvaluatedAt: Date?

  public init(
    folders: [WatchedFolderReminderState] = [],
    lastEvaluatedAt: Date? = nil
  ) {
    self.folders = folders
    self.lastEvaluatedAt = lastEvaluatedAt
  }
}

public protocol WatchedItemReminderStateStoring: Sendable {
  func load() throws -> WatchedItemReminderStateDocument
  func save(_ state: WatchedItemReminderStateDocument) throws
}

public struct FileWatchedItemReminderStateStore: WatchedItemReminderStateStoring, Sendable {
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load() throws -> WatchedItemReminderStateDocument {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return .init() }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(
      WatchedItemReminderStateDocument.self,
      from: Data(contentsOf: fileURL)
    )
  }

  public func save(_ state: WatchedItemReminderStateDocument) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(state)
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: fileURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
  }
}
