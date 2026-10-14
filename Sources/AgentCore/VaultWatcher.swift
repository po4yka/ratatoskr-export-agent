import Foundation

/// Turns vault observations into the ordered changes of a batch.
///
/// A create and a delete of two paths with equal hashes within
/// `pairingWindow` become one `renamed` change, in either order (design D5:
/// a rename outside Obsidian arrives as a create and, about 1 second later, a
/// delete). An unpaired create or delete waits for the window and then leaves
/// as it is. Changes leave in the order of observation.
///
/// When more than one waiting event can complete a pair, `VaultPairRank`
/// chooses the partner.
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

  /// The second opinion on a hash pair. `VaultModeCoordinator` asks it once
  /// per scan batch, outside its lock.
  public let renameCheck: any VaultRenameChecking
  private var entries: [Entry] = []
  private var nextSequence: UInt64

  /// `firstSequence` is the committed sequence plus 1.
  public init(firstSequence: UInt64, renameCheck: any VaultRenameChecking = HashPairingOnly()) {
    nextSequence = firstSequence
    self.renameCheck = renameCheck
  }

  /// Records one observation at the time the agent made it. Asks the rename
  /// check only when the observation can make a hash pair.
  public mutating func record(_ observation: VaultObservation, at time: Date) {
    let answer = needsRenameCheck([observation], at: time) ? renameCheck.answer() : .unavailable
    record(observation, at: time, answer: answer)
  }

  /// Records one observation of a scan batch with the answer that the rename
  /// check gave for that batch.
  public mutating func record(_ observation: VaultObservation, at time: Date, answer: VaultRenameAnswer) {
    switch observation {
    case let .modified(path, sha256, byteLength):
      entries.append(.ready(Draft(kind: .updated, path: path, sha256: sha256, byteLength: byteLength)))
    case let .created(path, sha256, _), let .deleted(path, sha256):
      guard let index = partnerIndex(of: path, sha256: sha256, isCreate: observation.isCreate, at: time, answer: answer)
      else {
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

  /// True when a create and a delete of two different paths with equal
  /// hashes can pair, among the waiting events and these observations. Only
  /// then does the rename check have something to answer.
  public func needsRenameCheck(_ observations: [VaultObservation], at time: Date) -> Bool {
    let waiting = entries.compactMap { entry -> VaultObservation? in
      guard case let .waiting(observation, observedAt) = entry,
        time.timeIntervalSince(observedAt) < Self.pairingWindow
      else {
        return nil
      }
      return observation
    }
    return VaultPairRank.holdsHashPair(waiting + observations)
  }

  /// The waiting entry of the opposite kind that this observation completes.
  private func partnerIndex(of path: String, sha256: String, isCreate: Bool, at time: Date, answer: VaultRenameAnswer) -> Int? {
    var best: (index: Int, rank: VaultPairRank)?
    for (index, entry) in entries.enumerated() {
      guard case let .waiting(other, observedAt) = entry,
        other.isCreate != isCreate,
        time.timeIntervalSince(observedAt) < Self.pairingWindow,
        let rank = VaultPairRank(of: other.path, against: path, sameHash: other.sha256 == sha256)
      else {
        continue
      }
      if let best, !(rank < best.rank) {
        continue
      }
      let (oldPath, newPath) = isCreate ? (other.path, path) : (path, other.path)
      if other.path != path, answer.verdict(renaming: oldPath, to: newPath) == .refuted {
        continue
      }
      best = (index, rank)
    }
    return best?.index
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
