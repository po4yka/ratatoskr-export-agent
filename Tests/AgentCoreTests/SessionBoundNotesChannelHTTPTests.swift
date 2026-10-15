@testable import AgentCore
import Foundation
import XCTest

final class SessionBoundNotesChannelHTTPTests: XCTestCase {
  override func tearDown() {
    ResumableURLProtocol.interceptor = nil
  }

  func testWithoutAPairedOriginNothingIsSent() async {
    let http = SessionBoundNotesChannelHTTP(origin: { nil }, authorizer: ScenarioAuthorizer())

    let error = await capturedError {
      _ = try await http.perform(NotesChannelRequest(method: "POST", path: "v1/notes/connections"))
      return ""
    }

    XCTAssertTrue(error is DeviceCredentialError, "an agent that is not paired sends nothing")
  }

  func testEachRequestUsesThePairedOriginOfThatMoment() async throws {
    let urls = SeenURLs()
    ResumableURLProtocol.interceptor = { request in
      urls.append(request.url?.absoluteString ?? "")
      return (200, Data("{}".utf8))
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ResumableURLProtocol.self]
    let origin = OriginBox(URL(string: "https://one.example")!)
    let http = SessionBoundNotesChannelHTTP(
      origin: { origin.value }, authorizer: ScenarioAuthorizer(), session: URLSession(configuration: configuration)
    )

    _ = try await http.perform(NotesChannelRequest(method: "GET", path: "v1/notes/connections"))
    origin.value = URL(string: "https://two.example")!
    _ = try await http.perform(NotesChannelRequest(method: "GET", path: "v1/notes/connections"))

    XCTAssertEqual(urls.values, ["https://one.example/v1/notes/connections", "https://two.example/v1/notes/connections"])
  }
}

private final class OriginBox: @unchecked Sendable {
  var value: URL?

  init(_ value: URL?) {
    self.value = value
  }
}

private final class SeenURLs: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: [String] = []

  var values: [String] { lock.withLock { stored } }

  func append(_ url: String) {
    lock.withLock { stored.append(url) }
  }
}
