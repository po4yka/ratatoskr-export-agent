import Foundation

/// A privacy-safe per-archive projection derived from local state or a Platform operation.
public enum BackendImportPresentation: Equatable, Codable, Sendable {
  case archived
  case uploading
  case processing
  case importedComplete
  case importedWithGaps(gapCount: Int)
  case failed
  case unverified
}

public extension BackendImportPresentation {
  /// Whether this projection represents an outcome that cannot progress further.
  var isTerminal: Bool {
    switch self {
    case .importedComplete, .importedWithGaps, .failed, .unverified:
      true
    case .archived, .uploading, .processing:
      false
    }
  }
}

/// The last privacy-safe fact observed for one Platform operation.
public struct BackendImportObservation: Codable, Equatable, Sendable {
  /// Platform's stable operation identity, never a provider identity.
  public let operationID: UUID
  /// The status derived solely from local lifecycle evidence or a valid operation payload.
  public let presentation: BackendImportPresentation
  /// When the agent successfully obtained this fact from Platform.
  public let observedAt: Date
  /// Platform's ordered status-change instant, when the operation payload exposed one.
  public let backendUpdatedAt: Date?
  /// Whether the generic terminal notice for this operation was delivered.
  public let terminalNoticeDelivered: Bool

  public init(
    operationID: UUID,
    presentation: BackendImportPresentation,
    observedAt: Date,
    backendUpdatedAt: Date? = nil,
    terminalNoticeDelivered: Bool = false
  ) {
    self.operationID = operationID
    self.presentation = presentation
    self.observedAt = observedAt
    self.backendUpdatedAt = backendUpdatedAt
    self.terminalNoticeDelivered = terminalNoticeDelivered
  }
}

/// A valid, bounded fact decoded from an operation snapshot.
public struct BackendImportOperationFact: Equatable, Sendable {
  public let presentation: BackendImportPresentation
  public let backendUpdatedAt: Date?
}

public enum BackendImportStatusError: Error, Equatable, Sendable {
  case invalidPayload
}

/// Decodes only the workspace-defined typed summary from a Platform operation response.
public enum BackendImportStatusMapper {
  public static func map(_ data: Data) throws -> BackendImportPresentation {
    try fact(from: data).presentation
  }

  /// Decodes a safe status fact, retaining Platform's ordering timestamp when present.
  public static func fact(from data: Data) throws -> BackendImportOperationFact {
    let payload: OperationPayload
    do {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      payload = try decoder.decode(OperationPayload.self, from: data)
    } catch {
      throw BackendImportStatusError.invalidPayload
    }

    switch payload.status {
    case "accepted", "queued", "running":
      return BackendImportOperationFact(presentation: .processing, backendUpdatedAt: payload.statusChangedAt)
    case "failed", "cancelled":
      return BackendImportOperationFact(presentation: .failed, backendUpdatedAt: payload.statusChangedAt)
    case "succeeded", "partially_succeeded":
      guard let summary = payload.results.first(where: { $0.validSummary != nil })?.validSummary else {
        return BackendImportOperationFact(presentation: .unverified, backendUpdatedAt: payload.statusChangedAt)
      }
      let presentation: BackendImportPresentation = summary.completeness == "complete"
        ? .importedComplete : .importedWithGaps(gapCount: summary.gapCount)
      return BackendImportOperationFact(presentation: presentation, backendUpdatedAt: payload.statusChangedAt)
    default:
      throw BackendImportStatusError.invalidPayload
    }
  }
}

private struct OperationPayload: Decodable {
  let status: String
  let results: [OperationResult]
  let statusChangedAt: Date?

  private enum CodingKeys: String, CodingKey { case status, results, statusChangedAt = "status_changed_at" }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    status = try values.decode(String.self, forKey: .status)
    results = try values.decodeIfPresent([OperationResult].self, forKey: .results) ?? []
    statusChangedAt = try values.decodeIfPresent(Date.self, forKey: .statusChangedAt)
  }
}

private struct OperationResult: Decodable {
  let resultKind: String
  let target: String
  let summary: ImportSummary?

  enum CodingKeys: String, CodingKey {
    case resultKind = "result_kind"
    case target
    case summary = "ai_archive_import_summary"
  }

  var validSummary: ImportSummary? {
    guard resultKind == "ai_archive.import", let summary,
          target == "ai_archive:\(summary.archiveID)", summary.isValid else { return nil }
    return summary
  }
}

private struct ImportSummary: Decodable {
  let archiveID: String
  let provider: String
  let completeness: String
  let conversationCount: Int
  let messageCount: Int
  let assetCount: Int
  let gapCount: Int
  let warningCount: Int

  enum CodingKeys: String, CodingKey {
    case archiveID = "ai_archive_id"
    case provider
    case completeness
    case conversationCount = "conversation_count"
    case messageCount = "message_count"
    case assetCount = "asset_count"
    case gapCount = "gap_count"
    case warningCount = "warning_count"
  }

  var isValid: Bool {
    let incomplete = ["conversations_complete", "structurally_partial", "assets_partial", "unknown", "failed_validation"]
    guard UUID(uuidString: archiveID) != nil, !provider.isEmpty,
          conversationCount >= 0, messageCount >= 0, assetCount >= 0, gapCount >= 0, warningCount >= 0 else {
      return false
    }
    if completeness == "complete" { return gapCount == 0 }
    return incomplete.contains(completeness) && gapCount > 0
  }
}
