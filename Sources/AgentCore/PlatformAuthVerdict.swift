import Foundation

/// Recognises Platform's own authentication verdict among `401` answers.
///
/// Platform answers a refused credential with an `ErrorEnvelope` whose `code` is
/// `platform.auth.unauthenticated`. A receiver's refusal relayed through Edge carries another code,
/// and an intermediary may send no envelope at all; neither says anything about the device
/// credential, so neither may cost the pairing (XR-021 CONTRACTS.md section R3-03 rule 4).
enum PlatformAuthVerdict {
  static let unauthenticatedCode = "platform.auth.unauthenticated"

  private struct Envelope: Decodable {
    let code: String
  }

  static func isPlatformUnauthenticated(_ body: Data) -> Bool {
    (try? JSONDecoder().decode(Envelope.self, from: body))?.code == unauthenticatedCode
  }

  /// The transport error for a `401`: `refused` only for Platform's own verdict, otherwise `unavailable`.
  static func transportError(forUnauthorizedBody body: Data) -> PlatformDeviceTransportError {
    isPlatformUnauthenticated(body) ? .refused : .unavailable
  }
}
