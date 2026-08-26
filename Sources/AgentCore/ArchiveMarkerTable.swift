import Foundation

/// One piece of shallow evidence a candidate can exhibit. Marker names only;
/// never archive content.
enum ArchiveMarker: Hashable, Sendable {
  /// A file entry at the top level of a zip.
  case topLevelFile(String)

  /// Any zip entry under the given folder prefix.
  case folderPrefix(String)

  /// A key at the top level of a json object or its first array element.
  case jsonKey(String)

  var displayName: String {
    switch self {
    case .topLevelFile(let name):
      "top-level \(name)"
    case .folderPrefix(let prefix):
      "folder \(prefix)*"
    case .jsonKey(let key):
      "key \(key)"
    }
  }
}

/// The marker set one provider requires for a confident label. Rows are
/// advisory routing data; backend services remain the parsing authority.
struct ProviderMarkerRow: Sendable {
  let provider: ArchiveProviderHint
  let required: Set<ArchiveMarker>
}

/// The outcome of matching observed markers against provider rows.
struct MarkerVerdict: Equatable, Sendable {
  let provider: ArchiveProviderHint
  let confidence: ClassificationConfidence?
  let matched: [String]
}

/// The classifier's marker tables. Isolated here so refining evidence
/// against real exports is a single-file change.
enum ArchiveMarkerTable {
  static let zipRows: [ProviderMarkerRow] = [
    ProviderMarkerRow(
      provider: .chatgpt,
      required: [.topLevelFile("conversations.json"), .topLevelFile("user.json")]
    ),
    ProviderMarkerRow(
      provider: .claude,
      required: [.topLevelFile("conversations.json"), .topLevelFile("users.json")]
    ),
    ProviderMarkerRow(
      provider: .instagram,
      required: [.folderPrefix("your_instagram_activity/")]
    ),
    ProviderMarkerRow(
      provider: .threads,
      required: [.folderPrefix("threads/")]
    ),
  ]

  static let jsonRows: [ProviderMarkerRow] = [
    ProviderMarkerRow(
      provider: .chatgpt,
      required: [.jsonKey("title"), .jsonKey("mapping"), .jsonKey("current_node")]
    ),
    ProviderMarkerRow(
      provider: .claude,
      required: [.jsonKey("chat_messages"), .jsonKey("uuid")]
    ),
  ]

  static func folderPrefixes(in rows: [ProviderMarkerRow]) -> [String] {
    rows.flatMap { row in
      row.required.compactMap { marker in
        if case .folderPrefix(let prefix) = marker {
          return prefix
        }
        return nil
      }
    }
  }

  /// The outcome of matching observed markers against provider rows.
  struct MarkerVerdict: Equatable, Sendable {
    let provider: ArchiveProviderHint
    let confidence: ClassificationConfidence?
    let matched: [String]
  }

  /// Labels observed markers against the rows: exactly one fully matched row
  /// is strong; partials confined to one provider are probable; anything
  /// spanning several providers is ambiguous rather than a guess.
  static func label(
    observed: Set<ArchiveMarker>,
    rows: [ProviderMarkerRow]
  ) -> MarkerVerdict {
    let fulls = rows.filter { observed.isSuperset(of: $0.required) }
    if fulls.count == 1, let full = fulls.first {
      return MarkerVerdict(
        provider: full.provider, confidence: .strong, matched: evidence(observed: observed))
    }
    let partials = rows.filter { !$0.required.isDisjoint(with: observed) }
    if fulls.count > 1 || partials.count > 1 {
      return MarkerVerdict(
        provider: .unidentified, confidence: .ambiguous, matched: evidence(observed: observed))
    }
    if let partial = partials.first {
      return MarkerVerdict(
        provider: partial.provider, confidence: .probable, matched: evidence(observed: observed))
    }
    return MarkerVerdict(provider: .unidentified, confidence: nil, matched: [])
  }

  private static func evidence(observed: Set<ArchiveMarker>) -> [String] {
    observed.map(\.displayName).sorted()
  }
}
