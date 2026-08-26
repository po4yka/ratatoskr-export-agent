import Foundation

/// Container format sniffed from leading magic bytes.
public enum ArchiveContainer: Equatable, Sendable {
  /// ZIP local-file-header signature.
  case zip

  /// JSON object or array after optional whitespace.
  case json

  /// Anything else, including empty files.
  case unknown
}

/// Provider labels this agent can suggest from shallow evidence. Labels are
/// advisory routing hints; backend services remain the parsing authority.
public enum ArchiveProviderHint: Equatable, Sendable {
  case chatgpt
  case claude
  case instagram
  case threads
  case unidentified
}

/// How strongly matched evidence supports the reported label.
public enum ClassificationConfidence: Equatable, Sendable {
  /// Every required marker of exactly one provider row was observed.
  case strong

  /// Some markers of one provider only were observed.
  case probable

  /// Partial evidence spans more than one provider row.
  case ambiguous
}

/// The shallow verdict for one candidate: container, advisory provider
/// label, confidence, and the marker names behind it. Evidence carries
/// marker names only, never archive content.
public struct ArchiveClassification: Equatable, Sendable {
  public let container: ArchiveContainer
  public let provider: ArchiveProviderHint
  public let confidence: ClassificationConfidence?
  public let matchedMarkers: [String]

  public init(
    container: ArchiveContainer,
    provider: ArchiveProviderHint,
    confidence: ClassificationConfidence?,
    matchedMarkers: [String]
  ) {
    self.container = container
    self.provider = provider
    self.confidence = confidence
    self.matchedMarkers = matchedMarkers
  }
}

/// Classifies candidates by magic bytes and bounded structure probes:
/// zip central-directory names and top-level json keys only. Nothing here
/// decompresses entry contents or reads beyond the bounded windows.
public struct ArchiveClassifier: Sendable {
  /// Bytes read from the file head for container sniffing.
  private let sniffByteCount = 4

  /// Prefix bytes inspected for top-level json keys.
  private let jsonProbeBytes = JSONTopLevelKeyScanner.maxPrefixBytes

  public init() {
  }

  public func classify(at url: URL) throws -> ArchiveClassification {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    guard size > 0 else {
      return ArchiveClassification(
        container: .unknown, provider: .unidentified, confidence: nil, matchedMarkers: [])
    }
    if startsWithZipSignature(url: url, size: Int(size)) {
      return classifyZip(at: url, fileSize: Int(size))
    }
    return classifyJsonish(at: url)
  }

  private func startsWithZipSignature(url: URL, size: Int) -> Bool {
    guard let head = readHead(url: url, count: max(sniffByteCount, 1), fileSize: size),
      head.count == sniffByteCount
    else {
      return false
    }
    return Array(head.prefix(sniffByteCount)) == [0x50, 0x4B, 0x03, 0x04]
  }

  private func classifyZip(at url: URL, fileSize: Int) -> ArchiveClassification {
    let listing =
      (try? ZipCentralDirectoryReader.listing(ofFileAt: url, fileSize: fileSize))
      ?? ZipCentralDirectoryListing.notFound()
    guard listing.foundDirectory else {
      return ArchiveClassification(
        container: .zip, provider: .unidentified, confidence: nil, matchedMarkers: [])
    }
    let observed = Self.observedZipMarkers(fromNames: listing.entryNames)
    let verdict = ArchiveMarkerTable.label(observed: observed, rows: ArchiveMarkerTable.zipRows)
    return ArchiveClassification(
      container: .zip,
      provider: verdict.provider,
      confidence: verdict.confidence,
      matchedMarkers: verdict.matched
    )
  }

  private func classifyJsonish(at url: URL) -> ArchiveClassification {
    guard let head = readHead(url: url, count: jsonProbeBytes, fileSize: jsonProbeBytes),
      Self.opensJSONValue(head)
    else {
      return ArchiveClassification(
        container: .unknown, provider: .unidentified, confidence: nil, matchedMarkers: [])
    }
    let observed = Set(
      JSONTopLevelKeyScanner.topLevelKeys(in: head).map(ArchiveMarker.jsonKey)
    )
    let verdict = ArchiveMarkerTable.label(observed: observed, rows: ArchiveMarkerTable.jsonRows)
    return ArchiveClassification(
      container: .json,
      provider: verdict.provider,
      confidence: verdict.confidence,
      matchedMarkers: verdict.matched
    )
  }

  private func readHead(url: URL, count: Int, fileSize: Int) -> Data? {
    guard let handle = try? FileHandle(forReadingFrom: url) else {
      return nil
    }
    defer {
      try? handle.close()
    }
    return try? handle.read(upToCount: min(count, fileSize))
  }

  private static func observedZipMarkers(fromNames names: [String]) -> Set<ArchiveMarker> {
    var observed = Set<ArchiveMarker>()
    let prefixes = ArchiveMarkerTable.folderPrefixes(in: ArchiveMarkerTable.zipRows)
    for name in names {
      if !name.contains("/") {
        observed.insert(.topLevelFile(name))
      }
      for prefix in prefixes where name.hasPrefix(prefix) {
        observed.insert(.folderPrefix(prefix))
      }
    }
    return observed
  }

  private static func opensJSONValue(_ data: Data) -> Bool {
    for byte in data where !isJSONWhitespace(byte) {
      return byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[")
    }
    return false
  }

  private static func isJSONWhitespace(_ byte: UInt8) -> Bool {
    byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\n")
      || byte == UInt8(ascii: "\r")
  }
}
