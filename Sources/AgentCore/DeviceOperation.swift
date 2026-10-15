import Foundation

/// One checked write in the queue of a `cli` connection, as
/// `GET /v1/notes/connections/{id}/device-operations` gives it (workspace spec
/// `notes-write-delivery`). `kind` is `create`, `update`, `rename`, `move`,
/// `delete` or `set_property`; the apply step fails any other kind.
public struct DeviceOperation: Decodable, Equatable, Sendable {
  public let operationID: String
  public let cursor: String
  public let kind: String
  public let path: String
  public let targetPath: String?
  public let baseHash: String?
  /// The SHA-256 of the bytes that `.../content` gives; nil when the
  /// operation has no bytes.
  public let contentSHA256: String?
  /// The `length_bytes` of the content; the read takes no more.
  public let contentLength: Int?
  public let propertyKey: String?
  public let propertyChange: String?
  public let expectedSHA256: String?
  /// The linking notes of a rename or a move; empty for any other kind.
  public let rewrites: [DeviceRewrite]

  enum CodingKeys: String, CodingKey {
    case operationID = "operation_id"
    case cursor
    case kind
    case path
    case targetPath = "target_path"
    case baseHash = "base_hash"
    case content
    case propertyKey = "property_key"
    case propertyChange = "property_change"
    case expectedSHA256 = "expected_sha256"
    case rewrites
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    operationID = try container.decode(String.self, forKey: .operationID)
    cursor = try container.decode(String.self, forKey: .cursor)
    kind = try container.decode(String.self, forKey: .kind)
    path = try container.decode(String.self, forKey: .path)
    targetPath = try container.decodeIfPresent(String.self, forKey: .targetPath)
    baseHash = try container.decodeIfPresent(String.self, forKey: .baseHash)
    let content = try container.decodeIfPresent(PlatformBlobReference.self, forKey: .content)
    contentSHA256 = content?.digest.hex
    contentLength = content?.lengthBytes
    propertyKey = try container.decodeIfPresent(String.self, forKey: .propertyKey)
    propertyChange = try container.decodeIfPresent(String.self, forKey: .propertyChange)
    expectedSHA256 = try container.decodeIfPresent(String.self, forKey: .expectedSHA256)
    rewrites = try container.decodeIfPresent([DeviceRewrite].self, forKey: .rewrites) ?? []
  }

  /// The path of the file after the operation.
  var resultPath: String {
    targetPath ?? path
  }
}

/// One page of the queue.
struct DeviceOperationPage: Decodable {
  let operations: [DeviceOperation]
  let nextCursor: String

  enum CodingKeys: String, CodingKey {
    case operations
    case nextCursor = "next_cursor"
  }
}

/// What the apply step did with one operation.
public enum DeviceOperationOutcome: Equatable, Sendable {
  /// The vault has the change; the file at the result path has this hash, or
  /// none after a delete. `rewrites` are the linking notes of a rename.
  case applied(sha256: String?, rewrites: [RewriteOutcome] = [])
  /// The local file did not have the base hash; nothing changed.
  case baseMismatch(localSHA256: String?)
  /// A linking note did not have its base hash; nothing of the group
  /// changed. `localSHA256` is the hash of the renamed file, and `rewrites`
  /// names every linking note with its own hash.
  case rewriteMismatch(localSHA256: String?, rewrites: [RewriteOutcome])
  /// The operation cannot be applied; the code names the cause.
  case failed(code: String)
  /// Obsidian does not run or its CLI does not answer; the operation stays
  /// in the queue.
  case awaitingObsidian
}

/// The body of `POST .../device-operations/{operation_id}/result`.
struct DeviceOperationResult: Encodable {
  let outcome: String
  let sha256: String?
  let localSHA256: String?
  let code: String?
  var rewrites: [RewriteResultBody] = []

  init?(_ outcome: DeviceOperationOutcome) {
    switch outcome {
    case .applied(let sha256, let rewrites):
      (self.outcome, self.sha256, localSHA256, code) = ("applied", sha256, nil, nil)
      self.rewrites = rewrites.map(RewriteResultBody.init(applied:))
    case .baseMismatch(let local): (self.outcome, sha256, localSHA256, code) = ("base_mismatch", nil, local, nil)
    case .rewriteMismatch(let local, let rewrites):
      (self.outcome, sha256, localSHA256, code) = ("base_mismatch", nil, local, nil)
      self.rewrites = rewrites.map(RewriteResultBody.init(mismatch:))
    case .failed(let code): (self.outcome, sha256, localSHA256, self.code) = ("failed", nil, nil, code)
    case .awaitingObsidian: return nil
    }
  }

  enum CodingKeys: String, CodingKey {
    case outcome
    case sha256
    case localSHA256 = "local_sha256"
    case code
    case rewrites
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(outcome, forKey: .outcome)
    try container.encodeIfPresent(sha256, forKey: .sha256)
    try container.encodeIfPresent(localSHA256, forKey: .localSHA256)
    try container.encodeIfPresent(code, forKey: .code)
    if !rewrites.isEmpty {
      try container.encode(rewrites, forKey: .rewrites)
    }
  }
}

/// How one pass over the queue ended.
public enum DeviceQueuePass: Equatable, Sendable {
  /// The agent answered this many operations, and no more wait.
  case answered(Int)
  /// Obsidian does not run or its CLI does not answer; the operations that
  /// were not answered stay in the queue.
  case awaitingObsidian
}
