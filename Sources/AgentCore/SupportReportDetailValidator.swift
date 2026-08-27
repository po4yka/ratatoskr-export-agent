import Foundation

enum SupportReportDetailValidator {
  static func validate(_ value: String, field: SupportReportSensitiveField) throws -> String {
    let limit = field == .filename ? 255 : 2_048
    guard !value.isEmpty, value.count <= limit else { throw SupportReportError.detailTooLong }
    guard !containsPath(value), !containsCredential(value) else {
      throw SupportReportError.prohibitedDetail
    }
    if field == .filename, value.contains("/") || value.contains("\\") {
      throw SupportReportError.prohibitedDetail
    }
    if field == .url {
      guard let components = URLComponents(string: value),
            ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
            components.host != nil,
            components.user == nil,
            components.password == nil
      else { throw SupportReportError.prohibitedDetail }
    }
    return value
  }

  private static func containsPath(_ value: String) -> Bool {
    let lowercase = value.lowercased()
    return value.hasPrefix("/") || lowercase.contains("/users/")
      || lowercase.contains("/volumes/") || lowercase.contains("file://")
      || lowercase.contains("\\users\\")
  }

  private static func containsCredential(_ value: String) -> Bool {
    guard let schemeEnd = value.range(of: "://")?.upperBound else {
      return value.localizedCaseInsensitiveContains("authorization: bearer ")
    }
    let authority = value[schemeEnd...].prefix { !$0.isWhitespace && $0 != "/" }
    guard let credentialSeparator = authority.firstIndex(of: "@") else { return false }
    return authority[..<credentialSeparator].contains(":")
  }
}
