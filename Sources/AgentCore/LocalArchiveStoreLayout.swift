import Foundation

// Layout, hygiene, and measurement concerns of the immutable archive
// store, kept beside the publishing core without growing its footprint.

extension LocalArchiveStore {
  /// Sums regular-file bytes under the given directory, recursively.
  public static func totalStoredBytes(under root: URL) throws -> Int {
    guard FileManager.default.fileExists(atPath: root.path) else {
      return 0
    }
    let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
    let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys)
    var total = 0
    while let url = enumerator?.nextObject() as? URL {
      let values = try? url.resourceValues(forKeys: Set(keys))
      if values?.isRegularFile == true {
        total += values?.fileSize ?? 0
      }
    }
    return total
  }

  /// Removes temporaries abandoned by earlier terminated publications while
  /// leaving anything recent enough to belong to a live publication alone.
  func sweepStaleTemporaries(in directory: URL, olderThan cutoff: Date) {
    let entries =
      (try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
      )) ?? []
    for entry in entries where entry.lastPathComponent.hasPrefix(Self.temporaryPrefix) {
      let modified =
        (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate ?? .distantPast
      if modified < cutoff {
        try? FileManager.default.removeItem(at: entry)
      }
    }
  }

  static func monthDirectory(
    providerSegment: String,
    calendarAnchor date: Date,
    root: URL
  ) -> URL {
    let components = Calendar.current.dateComponents([.year, .month], from: date)
    return
      root
      .appendingPathComponent(providerSegment, isDirectory: true)
      .appendingPathComponent(String(components.year ?? 0), isDirectory: true)
      .appendingPathComponent(String(format: "%02d", components.month ?? 0), isDirectory: true)
  }

  static func segmentName(for provider: ArchiveProviderHint) -> String {
    switch provider {
    case .chatgpt:
      "chatgpt"
    case .claude:
      "claude"
    case .instagram:
      "instagram"
    case .threads:
      "threads"
    case .unidentified:
      "unidentified"
    }
  }

  static func extensionName(for container: ArchiveContainer) -> String {
    switch container {
    case .zip:
      ".zip"
    case .json:
      ".json"
    case .unknown:
      ".bin"
    }
  }
}
