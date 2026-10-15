import Foundation

/// The body of `POST /v1/notes/connections` for the `cli` channel.
struct NotesConnectBody: Encodable {
  let channel = "cli"
  let vaultKey: String
  let vaultDisplayName: String

  enum CodingKeys: String, CodingKey {
    case channel
    case vaultKey = "vault_key"
    case vaultDisplayName = "vault_display_name"
  }
}

/// The `202` answer of Edge: the answer of the notes service is under
/// `connection`.
struct NotesConnectAccepted: Decodable {
  let connection: NotesConnection
}

struct NotesConnection: Decodable {
  let connectionID: String

  enum CodingKeys: String, CodingKey {
    case connectionID = "connection_id"
  }
}

struct NotesBatchCommitted: Decodable {
  let committedSequence: UInt64

  enum CodingKeys: String, CodingKey {
    case committedSequence = "committed_sequence"
  }
}

struct NotesManifestAnswer: Decodable {
  let neededSHA256: [String]
  let committedSequence: UInt64

  enum CodingKeys: String, CodingKey {
    case neededSHA256 = "needed_sha256"
    case committedSequence = "committed_sequence"
  }
}

/// The error envelope of a refused request, with the extensions of the
/// device routes.
struct NotesFault: Decodable {
  let code: String
  let committedSequence: UInt64?
  let missingSHA256: [String]?
  let retryable: Bool?

  enum CodingKeys: String, CodingKey {
    case code
    case retryable
    case committedSequence = "committed_sequence"
    case missingSHA256 = "missing_sha256"
  }

  static let notFound = "notes.connection.not_found"
  static let removed = "notes.connection.removed"
  static let channelMismatch = "notes.channel_mismatch"
  static let sequenceGap = "notes.channel.sequence_gap"
  static let bytesMissing = "notes.channel.bytes_missing"
  static let operationNotFound = "notes.device_operation.not_found"
  static let vaultAlreadyConnected = "notes.connection.vault_already_connected"
  static let invalidRequest = "notes.request.invalid"
  /// The cause of a stop that the agent names itself: notes takes at most
  /// 100 000 manifest entries and 32 MiB of manifest body.
  static let manifestTooLarge = "export_agent.manifest_too_large"
  static let maximumManifestEntries = 100_000

  static func of(_ answer: NotesChannelAnswer) -> NotesFault? {
    try? JSONDecoder().decode(NotesFault.self, from: answer.body)
  }

  /// The error of an answer that no route handles.
  static func error(of answer: NotesChannelAnswer) -> NotesChannelError {
    let code = of(answer)?.code
    switch (answer.status, code) {
    case (404, notFound): return .connectionGone
    case (410, removed): return .connectionRemoved
    case (409, vaultAlreadyConnected), (400, invalidRequest): return .permanent(code: code ?? "")
    case (409, channelMismatch): return .channelMismatch
    default: return .refused(status: answer.status, code: code)
    }
  }
}

func decodeNotesAnswer<Value: Decodable>(_ type: Value.Type, from answer: NotesChannelAnswer) throws -> Value {
  do {
    return try JSONDecoder().decode(type, from: answer.body)
  } catch {
    throw NotesChannelError.invalidAnswer
  }
}
