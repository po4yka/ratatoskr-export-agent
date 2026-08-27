import Foundation

public enum SupportReportSensitiveField: String, Codable, Hashable, Sendable {
  case filename
  case textDetail
  case url
}

public struct SupportReportDetailSelection: Hashable, Sendable {
  public let itemID: UUID
  public let field: SupportReportSensitiveField

  public init(itemID: UUID, field: SupportReportSensitiveField) {
    self.itemID = itemID
    self.field = field
  }
}

public struct SupportReportReviewedItemDetail: Equatable, Sendable {
  public let itemID: UUID
  public let filename: String?
  public let textDetail: String?
  public let url: String?

  public init(
    itemID: UUID,
    filename: String? = nil,
    textDetail: String? = nil,
    url: String? = nil
  ) {
    self.itemID = itemID
    self.filename = filename
    self.textDetail = textDetail
    self.url = url
  }
}

struct SupportReportEncodedItem: Encodable {
  let id: UUID
  let state: JournalState
  let byteSize: Int
  let attemptCount: Int
  let digestPrefix: String
  let details: SupportReportIncludedDetails?
}

struct SupportReportIncludedDetails: Encodable {
  let filename: String?
  let textDetail: String?
  let url: String?
}

enum SupportReportDetailIncluder {
  static func makeItems(
    summaries: [SupportReportItemSummary],
    reviewedDetails: [SupportReportReviewedItemDetail],
    selections: Set<SupportReportDetailSelection>
  ) throws -> [SupportReportEncodedItem] {
    let summaryIDs = Set(summaries.map(\.id))
    guard summaryIDs.count == summaries.count,
          selections.allSatisfy({ summaryIDs.contains($0.itemID) })
    else { throw SupportReportError.prohibitedDetail }
    var details: [UUID: SupportReportReviewedItemDetail] = [:]
    for detail in reviewedDetails {
      guard details.updateValue(detail, forKey: detail.itemID) == nil else {
        throw SupportReportError.prohibitedDetail
      }
    }
    return try summaries.sorted { $0.id.uuidString < $1.id.uuidString }.map { summary in
      let included = try include(
        details: details[summary.id],
        selections: selections.filter { $0.itemID == summary.id }
      )
      return SupportReportEncodedItem(
        id: summary.id,
        state: summary.state,
        byteSize: summary.byteSize,
        attemptCount: summary.attemptCount,
        digestPrefix: summary.digestPrefix,
        details: included
      )
    }
  }

  private static func include(
    details: SupportReportReviewedItemDetail?,
    selections: Set<SupportReportDetailSelection>
  ) throws -> SupportReportIncludedDetails? {
    guard !selections.isEmpty, let details else {
      if selections.isEmpty { return nil }
      throw SupportReportError.prohibitedDetail
    }
    let filename = try selected(.filename, from: details, selections: selections)
    let text = try selected(.textDetail, from: details, selections: selections)
    let url = try selected(.url, from: details, selections: selections)
    return SupportReportIncludedDetails(filename: filename, textDetail: text, url: url)
  }

  private static func selected(
    _ field: SupportReportSensitiveField,
    from details: SupportReportReviewedItemDetail,
    selections: Set<SupportReportDetailSelection>
  ) throws -> String? {
    guard selections.contains(.init(itemID: details.itemID, field: field)) else { return nil }
    let value: String?
    switch field {
    case .filename: value = details.filename
    case .textDetail: value = details.textDetail
    case .url: value = details.url
    }
    guard let value else { throw SupportReportError.prohibitedDetail }
    return try SupportReportDetailValidator.validate(value, field: field)
  }
}
