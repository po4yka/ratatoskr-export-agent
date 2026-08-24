import Foundation

public enum LogRedactor {
  private static let placeholder = "<path>"

  private static let homeRelativePath = compiledRegex("~/[A-Za-z0-9._/-]+")
  private static let absolutePOSIXPath = compiledRegex(
    "(?:/[A-Za-z0-9._-]+){2,}")
  private static let bareFilename = compiledRegex(
    "\\b[A-Za-z0-9_][A-Za-z0-9_-]*\\.[A-Za-z]{2,}\\b")

  private static func compiledRegex(_ pattern: String) -> NSRegularExpression {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      preconditionFailure("LogRedactor pattern must compile: \(pattern)")
    }
    return regex
  }

  public static func redact(_ message: String) -> String {
    let afterHomeRelative = replacingMatches(of: homeRelativePath, in: message)
    let afterAbsolutePaths = replacingMatches(of: absolutePOSIXPath, in: afterHomeRelative)
    return replacingMatches(of: bareFilename, in: afterAbsolutePaths)
  }

  private static func replacingMatches(of pattern: NSRegularExpression, in text: String) -> String {
    let mutable = NSMutableString(string: text)
    pattern.replaceMatches(
      in: mutable,
      range: NSRange(location: 0, length: mutable.length),
      withTemplate: placeholder
    )
    return mutable as String
  }
}
