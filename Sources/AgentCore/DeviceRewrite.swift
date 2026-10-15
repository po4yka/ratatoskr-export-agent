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

/// A linking note after the CLI: its hash, or nil when the note is gone.
public struct RewriteOutcome: Equatable, Sendable {
  public let path: String
  public let sha256: String?
}

/// One entry of `rewrites` in an `applied` result: `applied` with the hash,
/// or `base_mismatch` for a note that is gone.
struct RewriteResultBody: Encodable {
  let outcome: String
  let path: String
  let sha256: String?

  init(_ rewrite: RewriteOutcome) {
    outcome = rewrite.sha256 == nil ? "base_mismatch" : "applied"
    path = rewrite.path
    sha256 = rewrite.sha256
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(outcome, forKey: .outcome)
    try container.encode(path, forKey: .path)
    try container.encodeIfPresent(sha256, forKey: .sha256)
  }

  enum CodingKeys: String, CodingKey {
    case outcome
    case path
    case sha256
  }
}
