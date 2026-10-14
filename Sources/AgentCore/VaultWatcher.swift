import Foundation

/// One file system fact about a vault file, after the agent read the disk.
public enum VaultObservation: Equatable, Sendable {
  case created(path: String, sha256: String, byteLength: Int)
  case modified(path: String, sha256: String, byteLength: Int)
  case deleted(path: String, sha256: String)
}

/// Turns vault observations into the ordered changes of a batch.
///
/// A create and a delete of two paths with equal hashes within
/// `pairingWindow` become one `renamed` change, in either order (design D5:
/// a rename outside Obsidian arrives as a create and, about 1 second later, a
/// delete). An unpaired create or delete waits for the window and then leaves
/// as it is. Changes leave in the order of observation.
public struct VaultWatcher: Sendable {
  public static let pairingWindow: TimeInterval = 3

  private struct Draft: Sendable {
    var kind: VaultChangeKind
    var path: String
    var previousPath: String?
    var sha256: String?
    var byteLength: Int?
  }

  private enum Entry: Sendable {
    case ready(Draft)
    case waiting(VaultObservation, Date)
  }

  private let renameCheck: any VaultRenameChecking
  private var entries: [Entry] = []
  private var nextSequence: UInt64

  /// `firstSequence` is the committed sequence plus 1.
  public init(firstSequence: UInt64, renameCheck: any VaultRenameChecking = HashPairingOnly()) {
    nextSequence = firstSequence
    self.renameCheck = renameCheck
  }

  /// Records one observation at the time the agent made it.
  public mutating func record(_ observation: VaultObservation, at time: Date) {
    switch observation {
    case let .modified(path, sha256, byteLength):
      entries.append(.ready(Draft(kind: .updated, path: path, sha256: sha256, byteLength: byteLength)))
    case let .created(path, sha256, _), let .deleted(path, sha256):
      guard let index = partnerIndex(of: path, sha256: sha256, isCreate: observation.isCreate, at: time) else {
        entries.append(.waiting(observation, time))
        return
      }
      pair(observation, with: index)
    }
  }

  /// Returns the changes that are final at `time`, each with its sequence.
  public mutating func drain(at time: Date) -> [VaultChange] {
    var changes: [VaultChange] = []
    while let first = entries.first {
      let draft: Draft
      switch first {
      case let .ready(ready):
        draft = ready
      case let .waiting(observation, observedAt):
        guard time.timeIntervalSince(observedAt) >= Self.pairingWindow else {
          return changes
        }
        draft = Self.unpaired(observation)
      }
      entries.removeFirst()
      changes.append(
        VaultChange(
          sequence: nextSequence,
          kind: draft.kind,
          path: draft.path,
          previousPath: draft.previousPath,
          sha256: draft.sha256,
          byteLength: draft.byteLength
        )
      )
      nextSequence += 1
    }
    return changes
  }

  /// The waiting entry of the opposite kind that this observation completes.
  private func partnerIndex(of path: String, sha256: String, isCreate: Bool, at time: Date) -> Int? {
    entries.firstIndex { entry in
      guard case let .waiting(other, observedAt) = entry,
        other.isCreate != isCreate,
        time.timeIntervalSince(observedAt) < Self.pairingWindow
      else {
        return false
      }
      if other.path == path {
        return true
      }
      guard other.sha256 == sha256 else {
        return false
      }
      let (oldPath, newPath) = isCreate ? (other.path, path) : (path, other.path)
      return renameCheck.verdict(renaming: oldPath, to: newPath) != .refuted
    }
  }

  /// Replaces the waiting partner with the change that the two events make.
  private mutating func pair(_ observation: VaultObservation, with index: Int) {
    guard case let .waiting(other, _) = entries[index] else {
      return
    }
    entries.remove(at: index)
    let (deleted, created) = observation.isCreate ? (other, observation) : (observation, other)
    guard case let .created(newPath, sha256, byteLength) = created else {
      return
    }
    if deleted.path != newPath {
      entries.append(
        .ready(Draft(kind: .renamed, path: newPath, previousPath: deleted.path, sha256: sha256, byteLength: byteLength))
      )
    } else if observation.isCreate {
      // The path was deleted and written again: one update of that path.
      entries.append(.ready(Draft(kind: .updated, path: newPath, sha256: sha256, byteLength: byteLength)))
    }
    // A path created and deleted inside the window never reaches Ratatoskr.
  }

  private static func unpaired(_ observation: VaultObservation) -> Draft {
    switch observation {
    case let .created(path, sha256, byteLength):
      Draft(kind: .created, path: path, sha256: sha256, byteLength: byteLength)
    case let .modified(path, sha256, byteLength):
      Draft(kind: .updated, path: path, sha256: sha256, byteLength: byteLength)
    case let .deleted(path, _):
      Draft(kind: .deleted, path: path)
    }
  }
}

extension VaultObservation {
  var isCreate: Bool {
    if case .created = self {
      return true
    }
    return false
  }

  /// The NFC path relative to the vault root.
  public var path: String {
    switch self {
    case let .created(path, _, _), let .modified(path, _, _), let .deleted(path, _):
      path
    }
  }

  /// The SHA-256 of the bytes, for a delete the last bytes seen.
  public var sha256: String {
    switch self {
    case let .created(_, sha256, _), let .modified(_, sha256, _), let .deleted(_, sha256):
      sha256
    }
  }
}
