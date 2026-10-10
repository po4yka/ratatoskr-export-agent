import Foundation

final class ResumableURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var recorder: ResumableRequestRecorder?

  /// Answers a request before the recorder sees it; returning nil defers to the recorder.
  nonisolated(unsafe) static var interceptor: ((URLRequest) -> (Int, Data)?)?

  override static func canInit(with request: URLRequest) -> Bool { true }
  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let result =
      Self.interceptor?(request) ?? Self.recorder?.response(for: request) ?? (500, Data())
    let response = HTTPURLResponse(
      url: request.url!, statusCode: result.0, httpVersion: "HTTP/1.1", headerFields: nil
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: result.1)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
