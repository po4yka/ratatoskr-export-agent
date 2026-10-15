@testable import AgentCore
import Foundation
import XCTest

final class NotesChannelHTTPTests: XCTestCase {
  override func tearDown() {
    ResumableURLProtocol.interceptor = nil
  }

  func testHTTPSBindingSendsTheDeviceCredentialToTheEdgePath() async throws {
    let seen = SeenRequests()
    ResumableURLProtocol.interceptor = { request in
      seen.append(request)
      return (202, Data(#"{"status":"accepted"}"#.utf8))
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ResumableURLProtocol.self]
    let http = PlatformNotesChannelHTTP(
      origin: URL(string: "https://ratatoskr.example")!,
      authorizer: ScenarioAuthorizer(),
      session: URLSession(configuration: configuration)
    )

    let answer = try await http.perform(
      NotesChannelRequest(method: "POST", path: "v1/notes/connections", body: Data("{}".utf8), contentType: "application/json")
    )

    XCTAssertEqual(answer, NotesChannelAnswer(status: 202, body: Data(#"{"status":"accepted"}"#.utf8)))
    let request = try XCTUnwrap(seen.requests.first)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.url?.absoluteString, "https://ratatoskr.example/v1/notes/connections")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-access")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
  }

  func testQueryOfThePathIsSentAsAQuery() async throws {
    let seen = SeenRequests()
    ResumableURLProtocol.interceptor = { request in
      seen.append(request)
      return (200, Data(#"{"operations":[],"next_cursor":"7"}"#.utf8))
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ResumableURLProtocol.self]
    let http = PlatformNotesChannelHTTP(
      origin: URL(string: "https://ratatoskr.example")!,
      authorizer: ScenarioAuthorizer(),
      session: URLSession(configuration: configuration)
    )

    _ = try await http.perform(NotesChannelRequest(method: "GET", path: "v1/notes/connections/c1/device-operations?after=7"))

    XCTAssertEqual(
      seen.requests.first?.url?.absoluteString, "https://ratatoskr.example/v1/notes/connections/c1/device-operations?after=7"
    )
  }

  func testABoundedBodyIsReadUpToItsBoundAndOneByte() async throws {
    ResumableURLProtocol.interceptor = { _ in (200, Data(repeating: 7, count: 100_000)) }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ResumableURLProtocol.self]
    let http = PlatformNotesChannelHTTP(
      origin: URL(string: "https://ratatoskr.example")!,
      authorizer: ScenarioAuthorizer(),
      session: URLSession(configuration: configuration)
    )

    let answer = try await http.perform(
      NotesChannelRequest(method: "GET", path: "v1/notes/connections/c1/device-operations/o1/content", maximumBodyBytes: 10)
    )

    XCTAssertEqual(answer.status, 200)
    XCTAssertEqual(answer.body.count, 11, "the bound and one byte, so the caller sees that the body passes it")
  }
}

private final class SeenRequests: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: [URLRequest] = []

  var requests: [URLRequest] { lock.withLock { stored } }

  func append(_ request: URLRequest) {
    lock.withLock { stored.append(request) }
  }
}
