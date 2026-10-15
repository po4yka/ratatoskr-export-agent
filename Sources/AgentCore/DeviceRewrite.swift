import Foundation

/// One linking note of a queued rename or move, whose links Obsidian
/// rewrites with it (workspace spec `notes-link-rewrite`).
public struct DeviceRewrite: Decodable, Equatable, Sendable {
  public let path: String
  public let baseHash: String?
  public let expectedSHA256: String?

  enum CodingKeys: String, CodingKey {
    case path
    case baseHash = "base_hash"
    case expectedSHA256 = "expected_sha256"
  }
}

/// A linking note: its hash, or nil when the note is gone. `differs` tells,
/// in a group refusal, that the note does not have its base hash.
public struct RewriteOutcome: Equatable, Sendable {
  public let path: String
  public let sha256: String?
  public var differs = false
}

/// One entry of `rewrites` in a result. In an `applied` result: `applied`
/// with the hash, or `base_mismatch` for a note that is gone. In a
/// `base_mismatch` result: `base_mismatch` with the note's own hash, or null;
/// notes refuses an `applied` entry there.
struct RewriteResultBody: Encodable {
  let outcome: String
  let path: String
  let sha256: String?

  init(applied rewrite: RewriteOutcome) {
    outcome = rewrite.sha256 == nil ? "base_mismatch" : "applied"
    path = rewrite.path
    sha256 = rewrite.sha256
  }

  init(mismatch rewrite: RewriteOutcome) {
    outcome = "base_mismatch"
    path = rewrite.path
    sha256 = rewrite.sha256
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(outcome, forKey: .outcome)
    try container.encode(path, forKey: .path)
    if outcome == "applied" {
      try container.encode(sha256, forKey: .sha256)
    } else {
      try container.encode(sha256, forKey: .localSHA256)
    }
  }

  enum CodingKeys: String, CodingKey {
    case outcome
    case path
    case sha256
    case localSHA256 = "local_sha256"
  }
}
