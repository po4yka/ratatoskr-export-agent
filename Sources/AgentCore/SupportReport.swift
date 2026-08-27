import Foundation

public enum SupportReportError: Error, Equatable, Sendable {
  case invalidDigest
  case invalidBuildInfo
  case invalidCounter
  case prohibitedDetail
  case detailTooLong
}

public struct SupportReportBuildInfo: Codable, Equatable, Sendable {
  public let version: String
  public let build: String

  public init(version: String, build: String) {
    self.version = version
    self.build = build
  }
}

public struct SupportReportItemSummary: Codable, Equatable, Sendable {
  public let id: UUID
  public let state: JournalState
  public let byteSize: Int
  public let attemptCount: Int
  public let digestPrefix: String

  public init(entry: JournalEntry) throws {
    let digest = entry.fingerprint.sha256Hex
    guard digest.count == 64,
          digest.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
    else { throw SupportReportError.invalidDigest }
    id = entry.id
    state = entry.state
    byteSize = entry.fingerprint.byteSize
    attemptCount = entry.uploadCheckpoint?.attemptCount ?? 0
    digestPrefix = String(digest.prefix(12))
  }
}

public enum SupportReportFailureClassification: String, Codable, Sendable {
  case permissionDenied
  case diskUnavailable
  case journalCorruption
  case authentication
  case network
  case unknown
}

public struct SupportReportFailureSummary: Codable, Equatable, Sendable {
  public let classification: SupportReportFailureClassification
  public let count: Int

  public init(classification: SupportReportFailureClassification, count: Int) {
    self.classification = classification
    self.count = count
  }
}

public enum SupportReportFailureClassifier {
  public static func classify(_ error: Error) -> SupportReportFailureClassification {
    if let journalError = error as? LocalJournalError,
       case .safeStop = journalError {
      return .journalCorruption
    }
    if let cocoaError = error as? CocoaError,
       cocoaError.code == .fileReadNoPermission || cocoaError.code == .fileWriteNoPermission {
      return .permissionDenied
    }
    return .unknown
  }
}

public enum SupportReportBuilder {
  public static func make(
    snapshot: OperationalDiagnosticsSnapshot,
    items: [SupportReportItemSummary],
    failures: [SupportReportFailureSummary],
    generatedAt: Date,
    buildInfo: SupportReportBuildInfo,
    reviewedDetails: [SupportReportReviewedItemDetail] = [],
    selections: Set<SupportReportDetailSelection> = []
  ) throws -> Data {
    guard isSafeBuildValue(buildInfo.version), isSafeBuildValue(buildInfo.build) else {
      throw SupportReportError.invalidBuildInfo
    }
    guard failures.allSatisfy({ $0.count >= 0 }) else {
      throw SupportReportError.invalidCounter
    }
    let encodedItems = try SupportReportDetailIncluder.makeItems(
      summaries: items,
      reviewedDetails: reviewedDetails,
      selections: selections
    )
    let report = SupportReportDocument(
      generatedAt: generatedAt,
      build: buildInfo,
      diagnostics: snapshot,
      items: encodedItems,
      failures: failures.sorted { $0.classification.rawValue < $1.classification.rawValue }
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(report)
  }

  private static func isSafeBuildValue(_ value: String) -> Bool {
    !value.isEmpty && value.count <= 64 && value.allSatisfy {
      $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0))
    }
  }
}

private struct SupportReportDocument: Encodable {
  let format = "ratatoskr-support-report"
  let generatedAt: Date
  let build: SupportReportBuildInfo
  let diagnostics: OperationalDiagnosticsSnapshot
  let items: [SupportReportEncodedItem]
  let failures: [SupportReportFailureSummary]
}
