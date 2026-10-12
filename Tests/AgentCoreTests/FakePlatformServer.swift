import Foundation
@testable import AgentCore

/// A stateful in-process stand-in for Platform's archive routes, served through `ResumableURLProtocol`.
/// It is a test double, not proof against a live Edge.
final class FakePlatformServer: @unchecked Sendable {
  struct Open: Equatable {
    let key: String
    let token: String
  }

  static let operationID = "00000000-0000-0000-0000-000000000221"

  private let lock = NSLock()
  private let fingerprint: ArchiveFingerprint
  private var overrideAnswer: ((URLRequest) -> (Int, Data)?)?
  private var storedOpens: [Open] = []
  private var received: [String: Set<Int>] = [:]
  private var dead = Set<String>()
  private var storedLog: [String] = []
  private var dropIndex: Int?
  private var dropsLeft = 0

  init(fingerprint: ArchiveFingerprint) { self.fingerprint = fingerprint }

  var opens: [Open] { lock.withLock { storedOpens } }
  var log: [String] { lock.withLock { storedLog } }

  /// Chunks received per token, in token order of opening.
  func chunks(for token: String) -> Set<Int> { lock.withLock { received[token] ?? [] } }

  /// Answers matching requests with the given status before any normal handling.
  func override(_ answer: @escaping (URLRequest) -> (Int, Data)?) {
    lock.withLock { overrideAnswer = answer }
  }

  /// Edge forgets a token when a chunk with this index arrives: that request and every later request
  /// for the token answer 404. Applies to the next `times` tokens.
  func dropToken(onChunk index: Int, times: Int) {
    lock.withLock {
      dropIndex = index
      dropsLeft = times
    }
  }

  func answer(_ request: URLRequest) -> (Int, Data) {
    lock.withLock {
      storedLog.append("\(request.httpMethod ?? "") \(request.url?.path ?? "")")
      if let overridden = overrideAnswer?(request) { return overridden }
      return handle(request)
    }
  }

  private func handle(_ request: URLRequest) -> (Int, Data) {
    let parts = (request.url?.path ?? "").split(separator: "/").map(String.init)
    let method = request.httpMethod ?? ""
    switch (method, parts.count) {
    case ("POST", 3): return (202, Self.json(#"{"operation_id":"\#(Self.operationID)","status":"accepted"}"#))
    case ("POST", 5): return open(key: request.value(forHTTPHeaderField: "Idempotency-Key") ?? "")
    case ("GET", 7): return status(token: parts[5])
    case ("PUT", 8): return chunk(token: parts[5], index: Int(parts[7]) ?? -1)
    case ("POST", 7): return finalize(token: parts[5])
    default: return (500, Data())
    }
  }

  private func open(key: String) -> (Int, Data) {
    let token = "rst_\(String(format: "%024d", storedOpens.count + 1))"
    storedOpens.append(Open(key: key, token: token))
    received[token] = []
    return (201, Self.json(#"{"resumption_token":"\#(token)","chunk_size_bytes":65536,"expires_at":"2030-01-01T00:00:00Z"}"#))
  }

  private func status(token: String) -> (Int, Data) {
    guard !dead.contains(token) else { return Self.gone }
    let indices = (received[token] ?? []).sorted().map(String.init).joined(separator: ",")
    return (200, Self.json(#"{"resumption_token":"\#(token)","session_state":"open","received_chunks":[\#(indices)]}"#))
  }

  private func chunk(token: String, index: Int) -> (Int, Data) {
    if !dead.contains(token), dropIndex == index, dropsLeft > 0 {
      dropsLeft -= 1
      dead.insert(token)
    }
    guard !dead.contains(token) else { return Self.gone }
    received[token, default: []].insert(index)
    return (204, Data())
  }

  private func finalize(token: String) -> (Int, Data) {
    guard !dead.contains(token) else { return Self.gone }
    let body = """
      {"outcome":"stored","blob_ref":{"owner_service":"platform",\
      "digest":{"algorithm":"sha256","hex":"\(fingerprint.sha256Hex)"},\
      "media_type":"application/zip","length_bytes":\(fingerprint.byteSize)}}
      """
    return (200, Self.json(body))
  }

  private static var gone: (Int, Data) {
    (404, json(#"{"code":"platform.archive.transfer_not_found","message":"No such transfer.","retryable":false}"#))
  }

  private static func json(_ text: String) -> Data { Data(text.utf8) }
}
