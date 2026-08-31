@testable import AgentCore
import Foundation
import XCTest

final class AuthenticatedPlatformTransportTests: XCTestCase {
  func testEveryTransferRequestObservesCurrentSessionAuthority() async throws {
    let recorder = AuthorizationRecorder()
    let authorizer = RotatingAuthorizer(credentials: ["access-1", "access-2", "access-3"])
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AuthorizationURLProtocol.self]
    AuthorizationURLProtocol.recorder = recorder
    let transport = PlatformArchiveHTTPTransport(
      origin: URL(string: "https://ratatoskr.example")!,
      authorizer: authorizer,
      session: URLSession(configuration: configuration)
    )
    let fingerprint = ArchiveFingerprint(
      sha256Hex: String(repeating: "d", count: 64), byteSize: 7
    )
    let prepared = try await transport.prepare(
      provider: .chatgpt, fingerprint: fingerprint, idempotencyKey: "stable-key"
    )
    let session = try await transport.openTransfer(
      provider: .chatgpt, operationID: prepared.operationID,
      declaration: BlobUploadDeclaration(
        fingerprint: fingerprint, mediaType: "application/zip", chunkSizeBytes: 65536
      ),
      idempotencyKey: "stable-key"
    )
    _ = try await transport.transferStatus(
      provider: .chatgpt, operationID: prepared.operationID, token: session.token
    )

    XCTAssertEqual(recorder.authorizations, ["Bearer access-1", "Bearer access-2", "Bearer access-3"])
  }

  func testOne401RecoversOnceAndRetriesTheSameRequest() async throws {
    let recorder = AuthorizationRecorder(rejectFirstCredential: "access-old")
    let authorizer = RotatingAuthorizer(credentials: ["access-old"], recovered: "access-new")
    let transport = makeTransport(recorder: recorder, authorizer: authorizer)
    let fingerprint = ArchiveFingerprint(sha256Hex: String(repeating: "e", count: 64), byteSize: 7)

    _ = try await transport.prepare(
      provider: .chatgpt, fingerprint: fingerprint, idempotencyKey: "stable-key"
    )

    let recoveryCount = await authorizer.recoveryCount
    let rejectedCredentials = await authorizer.rejectedCredentials
    XCTAssertEqual(recorder.authorizations, ["Bearer access-old", "Bearer access-new"])
    XCTAssertEqual(recoveryCount, 1)
    XCTAssertEqual(rejectedCredentials, [])
  }

  func testSecond401RevokesRecoveredAuthority() async throws {
    let recorder = AuthorizationRecorder(rejectEveryCredential: true)
    let authorizer = RotatingAuthorizer(credentials: ["access-old"], recovered: "access-new")
    let transport = makeTransport(recorder: recorder, authorizer: authorizer)
    let fingerprint = ArchiveFingerprint(sha256Hex: String(repeating: "f", count: 64), byteSize: 7)

    await XCTAssertThrowsErrorAsync {
      _ = try await transport.prepare(
        provider: .claude, fingerprint: fingerprint, idempotencyKey: "stable-key"
      )
    }

    let recoveryCount = await authorizer.recoveryCount
    let rejectedCredentials = await authorizer.rejectedCredentials
    XCTAssertEqual(recorder.authorizations, ["Bearer access-old", "Bearer access-new"])
    XCTAssertEqual(recoveryCount, 1)
    XCTAssertEqual(rejectedCredentials, ["access-new"])
  }

  func testOperationPollAlsoObtainsRequestScopedAuthority() async throws {
    let recorder = AuthorizationRecorder()
    let authorizer = RotatingAuthorizer(credentials: ["poll-access"])
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AuthorizationURLProtocol.self]
    AuthorizationURLProtocol.recorder = recorder
    let poller = URLSessionBackendOperationPoller(
      origin: URL(string: "https://ratatoskr.example")!,
      authorizer: authorizer,
      session: URLSession(configuration: configuration)
    )

    _ = try await poller.fetchOperation(
      UUID(uuidString: "00000000-0000-0000-0000-000000000232")!
    )

    XCTAssertEqual(recorder.authorizations, ["Bearer poll-access"])
  }

  private func makeTransport(
    recorder: AuthorizationRecorder,
    authorizer: RotatingAuthorizer
  ) -> PlatformArchiveHTTPTransport {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AuthorizationURLProtocol.self]
    AuthorizationURLProtocol.recorder = recorder
    return PlatformArchiveHTTPTransport(
      origin: URL(string: "https://ratatoskr.example")!,
      authorizer: authorizer,
      session: URLSession(configuration: configuration)
    )
  }
}

private final class AuthorizationRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private let rejectFirstCredential: String?
  private let rejectEveryCredential: Bool
  private var values: [String] = []
  var authorizations: [String] { lock.withLock { values } }

  init(rejectFirstCredential: String? = nil, rejectEveryCredential: Bool = false) {
    self.rejectFirstCredential = rejectFirstCredential
    self.rejectEveryCredential = rejectEveryCredential
  }

  func response(for request: URLRequest) -> (Int, Data) {
    let authorization = request.value(forHTTPHeaderField: "Authorization") ?? "missing"
    let shouldReject = lock.withLock { () -> Bool in
      values.append(authorization)
      return rejectEveryCredential
        || (values.count == 1 && authorization == "Bearer \(rejectFirstCredential ?? "")")
    }
    if shouldReject { return (401, Data()) }
    let path = request.url?.path ?? ""
    if path == "/v1/ai-archives/chatgpt" {
      return (202, Data(#"{"operation_id":"00000000-0000-0000-0000-000000000231","status":"accepted"}"#.utf8))
    }
    if path.hasSuffix("/uploads") {
      return (
        201,
        Data(#"{"resumption_token":"session-231","chunk_size_bytes":65536}"#.utf8)
      )
    }
    return (
      200,
      Data(#"{"resumption_token":"session-231","received_chunks":[]}"#.utf8)
    )
  }
}

private actor RotatingAuthorizer: PlatformRequestAuthorizing {
  private var credentials: [String]
  private let recovered: String
  private(set) var recoveryCount = 0
  private(set) var rejectedCredentials: [String] = []

  init(credentials: [String], recovered: String = "unused-recovered") {
    self.credentials = credentials
    self.recovered = recovered
  }

  func credentialForRequest() async throws -> String {
    if credentials.count > 1 { return credentials.removeFirst() }
    return credentials[0]
  }

  func recoverCredential(afterRejectedCredential _: String) async throws -> String {
    recoveryCount += 1
    return recovered
  }

  func authorizationWasRejected(_ credential: String) async {
    rejectedCredentials.append(credential)
  }
}

private final class AuthorizationURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var recorder: AuthorizationRecorder?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let result = Self.recorder?.response(for: request) ?? (500, Data())
    let response = HTTPURLResponse(
      url: request.url!, statusCode: result.0, httpVersion: "HTTP/1.1", headerFields: nil
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: result.1)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
