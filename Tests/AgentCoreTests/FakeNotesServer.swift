import AgentCore
import CryptoKit
import Foundation

/// A stateful in-process stand-in for the device routes of `ratatoskr-notes`
/// behind Edge. It is a test double, not proof against a live Edge.
final class FakeNotesServer: NotesChannelHTTP, @unchecked Sendable {
  private let lock = NSLock()
  private var storedLog: [NotesChannelRequest] = []
  private var scripted: [(suffix: String, answer: NotesChannelAnswer)] = []
  private var connections = 0
  private var stored: Set<String> = []
  private var chunks: [String: [Int: Data]] = [:]
  /// The committed device sequence of the connection.
  var committed: UInt64 {
    get { lock.withLock { storedCommitted } }
    set { lock.withLock { storedCommitted = newValue } }
  }
  private var storedCommitted: UInt64 = 0
  /// The largest batch before `batch_too_large`; notes takes 256.
  var maximumChanges = 256

  var log: [NotesChannelRequest] { lock.withLock { storedLog } }

  /// Every request as `METHOD path`, with the connection id as `{id}`.
  var routes: [String] {
    log.map { "\($0.method) \($0.path.replacingOccurrences(of: Self.idPattern, with: "{id}", options: .regularExpression))" }
  }

  /// The sequences of each change batch, in send order.
  var batches: [[UInt64]] {
    log.filter { $0.path.hasSuffix("/changes") }.compactMap { request in
      (try? JSONDecoder().decode(VaultChangeBatch.self, from: request.body ?? Data()))?.changes.map(\.sequence)
    }
  }

  /// Answers the next request whose path ends with `suffix` with this status and body.
  func script(_ suffix: String, status: Int, body: String) {
    lock.withLock { scripted.append((suffix, NotesChannelAnswer(status: status, body: Data(body.utf8)))) }
  }

  func perform(_ request: NotesChannelRequest) async throws -> NotesChannelAnswer {
    lock.withLock {
      storedLog.append(request)
      if let index = scripted.firstIndex(where: { request.path.hasSuffix($0.suffix) }) {
        return scripted.remove(at: index).answer
      }
      return answer(request)
    }
  }

  private static let idPattern = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"

  private func answer(_ request: NotesChannelRequest) -> NotesChannelAnswer {
    let parts = request.path.split(separator: "/").map(String.init)
    switch (request.method, parts.count, parts.last ?? "") {
    case ("POST", 3, _): return connect()
    case ("POST", 5, "manifest"): return manifest(request.body)
    case ("POST", 5, "changes"): return changes(request.body)
    case ("POST", 5, "blobs"): return open(request.body)
    case ("PUT", 8, _):
      chunks[parts[5], default: [:]][Int(parts[7]) ?? -1] = request.body ?? Data()
      return Self.json(200, #"{"received_bytes":0}"#)
    case ("GET", 7, "status"):
      let indices = (chunks[parts[5]] ?? [:]).keys.sorted().map(String.init).joined(separator: ",")
      return Self.json(200, #"{"resumption_token":"\#(parts[5])","received_chunks":[\#(indices)]}"#)
    case ("POST", 7, "finalize"): return finalize(token: parts[5])
    default: return Self.json(500, "{}")
    }
  }

  private func connect() -> NotesChannelAnswer {
    connections += 1
    let id = String(format: "00000000-0000-7000-8000-%012d", connections)
    return Self.json(
      202,
      #"{"operation_id":"00000000-0000-7000-8000-0000000000aa","status":"accepted","connection":"#
        + #"{"connection_id":"\#(id)","channel":"cli","state":"connecting"}}"#
    )
  }

  private func manifest(_ body: Data?) -> NotesChannelAnswer {
    let entries = (try? JSONDecoder().decode(VaultManifest.self, from: body ?? Data()))?.entries ?? []
    let needed = Set(entries.filter { $0.lengthBytes > 0 && !stored.contains($0.sha256) }.map(\.sha256)).sorted()
    let list = needed.map { "\"\($0)\"" }.joined(separator: ",")
    return Self.json(200, #"{"needed_sha256":[\#(list)],"committed_sequence":\#(storedCommitted)}"#)
  }

  private func changes(_ body: Data?) -> NotesChannelAnswer {
    let changes = (try? JSONDecoder().decode(VaultChangeBatch.self, from: body ?? Data()))?.changes ?? []
    guard changes.count <= maximumChanges else {
      return Self.json(413, #"{"code":"notes.channel.batch_too_large","message":"m","retryable":false,"max_changes":256}"#)
    }
    if changes.contains(where: { $0.kind != .deleted && ($0.sha256 == nil || $0.byteLength == nil) }) {
      return Self.json(400, #"{"code":"notes.request.invalid","message":"m","retryable":false}"#)
    }
    if let first = changes.first, first.sequence > storedCommitted + 1 {
      return Self.json(
        409,
        #"{"code":"notes.channel.sequence_gap","message":"m","retryable":false,"committed_sequence":\#(storedCommitted)}"#
      )
    }
    let missing = Set(changes.compactMap { change in
      (change.byteLength ?? 0) > 0 && !stored.contains(change.sha256 ?? "") ? change.sha256 : nil
    }).sorted()
    guard missing.isEmpty else {
      let list = missing.map { "\"\($0)\"" }.joined(separator: ",")
      return Self.json(409, #"{"code":"notes.channel.bytes_missing","message":"m","retryable":false,"missing_sha256":[\#(list)]}"#)
    }
    storedCommitted = max(storedCommitted, changes.last?.sequence ?? 0)
    return Self.json(200, #"{"committed_sequence":\#(storedCommitted)}"#)
  }

  private func open(_ body: Data?) -> NotesChannelAnswer {
    let declaration = try? JSONDecoder().decode(BlobUploadDeclaration.self, from: body ?? Data())
    let token = "nst_\(chunks.count + 1)"
    chunks[token] = [:]
    let size = declaration?.chunkSizeBytes ?? 0
    return Self.json(201, #"{"resumption_token":"\#(token)","chunk_size_bytes":\#(size),"expires_at":"2030-01-01T00:00:00Z"}"#)
  }

  private func finalize(token: String) -> NotesChannelAnswer {
    let bytes = (chunks[token] ?? [:]).sorted { $0.key < $1.key }.reduce(into: Data()) { $0 += $1.value }
    let hex = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    stored.insert(hex)
    return Self.json(
      200,
      #"{"outcome":"stored","blob_ref":{"owner_service":"notes","digest":{"algorithm":"sha256","hex":"\#(hex)"},"#
        + #""media_type":"application/octet-stream","length_bytes":\#(bytes.count)}}"#
    )
  }

  private static func json(_ status: Int, _ text: String) -> NotesChannelAnswer {
    NotesChannelAnswer(status: status, body: Data(text.utf8))
  }
}
