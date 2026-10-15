import Foundation

/// A linking note of a rename group with its URL in the vault.
struct LinkingNote: Sendable {
  let rewrite: DeviceRewrite
  let url: URL
}

extension ObsidianCLIApply {
  /// The linking notes of the operation with their URLs, or nil when one path
  /// is refused.
  func linkingNotes(of operation: DeviceOperation) -> [LinkingNote]? {
    var notes: [LinkingNote] = []
    for rewrite in operation.rewrites {
      guard let url = files.url(of: rewrite.path) else {
        return nil
      }
      notes.append(LinkingNote(rewrite: rewrite, url: url))
    }
    return notes
  }

  /// A refusal of the whole group when a linking note does not have its
  /// base hash: the hash of the renamed file `local`, and every note with
  /// its own hash; nil when every note has its base hash.
  func rewriteMismatch(_ notes: [LinkingNote], local: String?) throws -> DeviceOperationOutcome? {
    let found = try notes.map { note in
      let hash = try files.sha256(at: note.url)
      return RewriteOutcome(path: note.rewrite.path, sha256: hash, differs: hash != note.rewrite.baseHash)
    }
    return found.contains(where: \.differs) ? .rewriteMismatch(localSHA256: local, rewrites: found) : nil
  }

  /// `outcome` with the hash of each linking note after the CLI. Obsidian
  /// can write a link after the CLI returned, so when a note still has its
  /// base hash and expects other bytes, each note is read once more after
  /// `settle`.
  func reportingRewrites(_ outcome: DeviceOperationOutcome, _ notes: [LinkingNote]) async throws -> DeviceOperationOutcome {
    guard case .applied(let sha256, _) = outcome, !notes.isEmpty else {
      return outcome
    }
    var hashes = try notes.map { try files.sha256(at: $0.url) }
    let waiting = zip(notes, hashes).contains { note, hash in
      hash == note.rewrite.baseHash && hash != note.rewrite.expectedSHA256
    }
    if waiting {
      await settle()
      hashes = try notes.map { try files.sha256(at: $0.url) }
    }
    return .applied(sha256: sha256, rewrites: zip(notes, hashes).map { RewriteOutcome(path: $0.rewrite.path, sha256: $1) })
  }
}
