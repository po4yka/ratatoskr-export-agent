import Foundation

/// The order in which the vault watcher prefers the partners of a create or a
/// delete; a lower rank is better.
///
/// First comes a different path with the same file name (a folder rename
/// moves `Old/X` to `New/X`), then the same path, then any other path with
/// an equal hash. Inside a group the nearest path wins: the most equal path
/// segments at the end, then the most equal characters at the start, then
/// the first path in path order.
struct VaultPairRank: Comparable {
  private let group: Int
  private let equalEnd: Int
  private let equalStart: Int
  private let path: String

  /// Nil when `other` and `path` cannot pair.
  init?(of other: String, against path: String, sameHash: Bool) {
    self.path = other
    if other == path {
      (group, equalEnd, equalStart) = (1, 0, 0)
      return
    }
    guard sameHash else {
      return nil
    }
    equalEnd = zip(other.split(separator: "/").reversed(), path.split(separator: "/").reversed()).prefix { $0 == $1 }.count
    equalStart = zip(other, path).prefix { $0 == $1 }.count
    group = equalEnd > 0 ? 0 : 2
  }

  static func < (lhs: Self, rhs: Self) -> Bool {
    (lhs.group, rhs.equalEnd, rhs.equalStart, lhs.path) < (rhs.group, lhs.equalEnd, lhs.equalStart, rhs.path)
  }

  /// True when the observations hold a create and a delete of two different
  /// paths with equal hashes.
  static func holdsHashPair(_ observations: [VaultObservation]) -> Bool {
    var created: [String: Set<String>] = [:]
    var deleted: [String: Set<String>] = [:]
    for observation in observations {
      switch observation {
      case .created:
        created[observation.sha256, default: []].insert(observation.path)
      case .deleted:
        deleted[observation.sha256, default: []].insert(observation.path)
      case .modified:
        break
      }
    }
    return created.contains { sha256, paths in
      guard let others = deleted[sha256] else {
        return false
      }
      return paths.count > 1 || others.count > 1 || paths != others
    }
  }
}
