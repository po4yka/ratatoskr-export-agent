import Foundation

/// Recognizes the temporary names browsers use while a download is still in
/// progress. A suffixed name is never queued; once the browser renames the
/// file to its final name the path becomes eligible as a fresh candidate.
public enum PartialDownloadHeuristics {
  /// Known temporary-download extensions, matched case-insensitively.
  static let knownExtensions: Set<String> = ["download", "crdownload", "part", "partial"]

  /// Whether this file name carries a known temporary download suffix.
  public static func hasTemporarySuffix(_ fileName: String) -> Bool {
    let pathExtension = (fileName as NSString).pathExtension.lowercased()
    return knownExtensions.contains(pathExtension)
  }
}
