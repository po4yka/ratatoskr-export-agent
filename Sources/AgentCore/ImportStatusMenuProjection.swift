import Foundation

/// Renders journal facts into privacy-safe per-archive menu rows.
public enum ImportStatusMenuProjection {
  /// Per-archive rows ordered by the local archive identity.
  public static func titles(entries: [JournalEntry]) -> [String] {
    entries.map(title(for:)).sorted()
  }

  private static func title(for entry: JournalEntry) -> String {
    let localID = String(entry.id.uuidString.prefix(8)).lowercased()
    if entry.state == .queued, let checkpoint = entry.uploadCheckpoint, checkpoint.control == .failed {
      return "\(localID): \(failedUploadTitle(checkpoint.failureReason))"
    }
    if let observation = entry.backendImport {
      let state = backendTitle(observation.presentation)
      guard observation.observedAt != .distantPast else { return "\(localID): \(state)" }
      return "\(localID): \(state) — last known \(timestamp(observation.observedAt))"
    }
    return "\(localID): \(localTitle(entry.state))"
  }

  private static func failedUploadTitle(_ reason: UploadCheckpoint.FailureReason?) -> String {
    switch reason {
    case .retriesExhausted: "Upload failed (retries exhausted)"
    case .sessionExpired: "Upload failed (session expired)"
    case nil: "Upload failed"
    }
  }

  private static func localTitle(_ state: JournalState) -> String {
    switch state {
    case .discovered, .archived, .hashed, .queued, .confirmed:
      "Archived locally"
    case .uploading, .uploaded:
      "Uploading"
    }
  }

  private static func backendTitle(_ presentation: BackendImportPresentation) -> String {
    switch presentation {
    case .archived:
      "Archived locally"
    case .uploading:
      "Uploading"
    case .processing:
      "Processing"
    case .importedComplete:
      "Imported complete"
    case .importedWithGaps:
      "Imported with gaps"
    case .failed:
      "Import failed"
    case .unverified:
      "Import status unverified"
    }
  }

  private static func timestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }
}
