import Foundation

/// The Platform archive route an answer came from. The same status means different things on different routes.
enum PlatformArchiveRoute: Sendable {
  case prepare
  case open
  case status
  case chunk
  case finalize
}

/// Maps one failed Platform answer on the archive routes to the error the upload queue classifies
/// (XR-021 CONTRACTS.md section R5-05 rule 1).
///
/// Precedence: `401`, `403` and `413` keep their meaning; then the explicit route rows; then the `retryable`
/// member of the `ErrorEnvelope` when the body parses as one; then the status class (408, 429 and 5xx are
/// retryable, every other 4xx is permanent). A retryable result carries `Retry-After` when the header is
/// present. The route rows come before the envelope because Platform marks a 404 for a dead session
/// `retryable: false`, yet reopening the session is the recovery.
struct PlatformAnswerClassifier {
  private struct Envelope: Decodable {
    let code: String
    let retryable: Bool
  }

  let route: PlatformArchiveRoute
  let statusCode: Int
  let body: Data
  let retryAfter: TimeInterval?

  init(route: PlatformArchiveRoute, response: HTTPURLResponse, body: Data) {
    self.route = route
    statusCode = response.statusCode
    self.body = body
    retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Self.wholeSeconds)
  }

  var error: any Error {
    switch statusCode {
    case 401: return PlatformAuthVerdict.transportError(forUnauthorizedBody: body)
    case 403: return PlatformDeviceTransportError.refusedPermanently
    case 413: return PlatformDeviceTransportError.payloadTooLarge
    case 400...599: return routeRule ?? envelopeOrStatusClass
    default: return PlatformDeviceTransportError.unavailable
    }
  }

  private var routeRule: (any Error)? {
    switch (route, statusCode) {
    case (.prepare, 400), (.prepare, 422), (.prepare, 409), (.open, 400), (.open, 422), (.open, 409):
      PlatformDeviceTransportError.refusedPermanently
    case (.prepare, 404), (.open, 404), (.chunk, 400), (.finalize, 400):
      retryableError
    case (.status, 404), (.chunk, 404), (.finalize, 404):
      BlobReceiptTransportError.expiredSession
    default:
      nil
    }
  }

  private var envelopeOrStatusClass: any Error {
    let statusRetryable = statusCode == 408 || statusCode == 429 || statusCode >= 500
    let envelope = try? JSONDecoder().decode(Envelope.self, from: body)
    return (envelope?.retryable ?? statusRetryable) ? retryableError : PlatformDeviceTransportError.refusedPermanently
  }

  private var retryableError: any Error {
    retryAfter.map { BlobReceiptTransportError.retryAfter($0) } ?? PlatformDeviceTransportError.unavailable
  }

  /// `Retry-After` as a positive number of whole seconds; the HTTP-date form is not used by Platform.
  private static func wholeSeconds(_ value: String) -> TimeInterval? {
    Int(value.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? TimeInterval($0) : nil }
  }
}
