import Foundation

public protocol DiskSpaceProbing: Sendable {
  func availableSpace(at directoryURL: URL) -> DiskSpaceDiagnostics
}

public struct FileManagerDiskSpaceProbe: DiskSpaceProbing, Sendable {
  public init() {}

  public func availableSpace(at directoryURL: URL) -> DiskSpaceDiagnostics {
    do {
      let values = try directoryURL.resourceValues(
        forKeys: [.volumeAvailableCapacityForImportantUsageKey]
      )
      guard let bytes = values.volumeAvailableCapacityForImportantUsage, bytes >= 0 else {
        return .unavailable
      }
      return .available(bytes: bytes)
    } catch {
      return .unavailable
    }
  }
}

public struct LocalJournalDiagnostics: Equatable, Sendable {
  public let health: JournalHealthDiagnostics
  public let queueStatus: UploadQueueStatus?

  public init(open journal: LocalArchiveJournal) {
    health = .healthy(entryCount: journal.entries.count)
    queueStatus = UploadQueueStatus(entries: journal.entries)
  }

  public init(openFailure: Error) {
    if let journalError = openFailure as? LocalJournalError,
       case .safeStop = journalError {
      health = .requiresAttention
    } else {
      health = .unavailable
    }
    queueStatus = nil
  }
}
