import Foundation

/// The transport-honest `UploadSessionRequest` shape from the fleet
/// blob-transfer contract. Idempotency is deliberately not a wire field.
public struct BlobUploadDeclaration: Codable, Equatable, Sendable {
  public struct Digest: Codable, Equatable, Sendable {
    public let algorithm: String
    public let hex: String
  }

  public let declaredSizeBytes: Int
  public let mediaType: String
  public let digest: Digest
  public let chunkSizeBytes: Int

  enum CodingKeys: String, CodingKey {
    case declaredSizeBytes = "declared_size_bytes"
    case mediaType = "media_type"
    case digest
    case chunkSizeBytes = "chunk_size_bytes"
  }

  public init(fingerprint: ArchiveFingerprint, mediaType: String, chunkSizeBytes: Int) {
    declaredSizeBytes = fingerprint.byteSize
    self.mediaType = mediaType
    digest = .init(algorithm: "sha256", hex: fingerprint.sha256Hex)
    self.chunkSizeBytes = chunkSizeBytes
  }
}

public struct BlobUploadSession: Equatable, Sendable {
  public let token: String
  public let chunkSizeBytes: Int

  public init(token: String, chunkSizeBytes: Int) {
    self.token = token
    self.chunkSizeBytes = chunkSizeBytes
  }
}

public struct BlobUploadStatus: Equatable, Sendable {
  public let receivedIndices: Set<Int>

  public init(receivedIndices: Set<Int>) {
    self.receivedIndices = receivedIndices
  }
}

public struct BlobStoredReceipt: Equatable, Sendable {
  public let sha256Hex: String
  public let byteSize: Int
  public let reference: String

  public init(sha256Hex: String, byteSize: Int, reference: String) {
    self.sha256Hex = sha256Hex
    self.byteSize = byteSize
    self.reference = reference
  }
}

public enum BlobReceiptTransportError: Error, Equatable, Sendable {
  case unavailable
  case retryAfter(TimeInterval)
  case expiredSession
  case capacityUnavailable
  case authentication
  case policy
  case validation
  case conflict
  case permanent
  case invalidReceipt
}

public protocol BlobReceiptTransport: Sendable {
  /// `idempotencyKey` is a digest-derived edge/client identity, not a
  /// blob-transfer wire field. A future authenticated edge binding owns it.
  func open(
    _ declaration: BlobUploadDeclaration,
    idempotencyKey: String
  ) async throws -> BlobUploadSession
  func status(token: String) async throws -> BlobUploadStatus
  func send(token: String, index: Int, bytes: Data) async throws
  func finalize(token: String) async throws -> BlobStoredReceipt
}

public enum BlobReceiptVerification {
  public static func verify(_ receipt: BlobStoredReceipt, fingerprint: ArchiveFingerprint) throws {
    guard receipt.sha256Hex == fingerprint.sha256Hex, receipt.byteSize == fingerprint.byteSize else {
      throw BlobReceiptTransportError.invalidReceipt
    }
  }
}
