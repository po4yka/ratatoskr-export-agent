import CryptoKit
import Foundation

/// The content identity of one archived candidate: lowercase hex SHA-256
/// digest plus the exact byte count hashed.
public struct ArchiveFingerprint: Equatable, Sendable {
  /// Lowercase hexadecimal SHA-256 of the hashed bytes.
  public let sha256Hex: String

  /// The exact number of bytes hashed.
  public let byteSize: Int

  public init(sha256Hex: String, byteSize: Int) {
    self.sha256Hex = sha256Hex
    self.byteSize = byteSize
  }
}

/// Why fingerprinting ended without producing a digest.
public enum StreamingHashError: Error, Equatable, Sendable {
  /// The source ended before its observed byte count had been read, so any
  /// digest would describe truncated content rather than the candidate.
  case sourceShrank(expectedByteCount: Int)
}

/// Chunked bytes feeding the hasher. The file-backed implementation serves
/// real candidate files; tests script sources for deterministic failures.
protocol ArchiveChunkSourcing: Sendable {
  /// The byte count the source claims to hold.
  var expectedByteCount: Int { get }

  /// The next chunk of at most `maxBytes`, or nil at end of input.
  mutating func nextChunk(maxBytes: Int) throws -> Data?
}

/// Serves an open file handle in bounded chunks against its declared size.
struct FileHandleChunkSource: ArchiveChunkSourcing {
  private let handle: FileHandle
  let expectedByteCount: Int

  init(handle: FileHandle, expectedByteCount: Int) {
    self.handle = handle
    self.expectedByteCount = expectedByteCount
  }

  mutating func nextChunk(maxBytes: Int) throws -> Data? {
    try handle.read(upToCount: maxBytes)
  }
}

/// Computes a candidate's SHA-256 identity by streaming bounded chunks so
/// memory stays flat regardless of archive size.
public struct StreamingHasher: Sendable {
  /// Largest single read issued against a source, in bytes.
  public let chunkSize: Int

  public init(chunkSize: Int = 1_048_576) {
    self.chunkSize = chunkSize
  }

  /// Fingerprints the file at the given URL, hashing exactly the byte count
  /// the filesystem reports so later growth cannot leak into the identity.
  public func fingerprint(at url: URL) throws -> ArchiveFingerprint {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    let handle = try FileHandle(forReadingFrom: url)
    defer {
      try? handle.close()
    }
    let source = FileHandleChunkSource(handle: handle, expectedByteCount: Int(size))
    return try fingerprint(source: source)
  }

  /// Hashes exactly `expectedByteCount` bytes from the source; an early end
  /// of input fails instead of yielding a digest of truncated content.
  func fingerprint<S: ArchiveChunkSourcing>(source: S) throws -> ArchiveFingerprint {
    var source = source
    var hasher = SHA256()
    var consumed = 0
    while consumed < source.expectedByteCount {
      let wanted = min(chunkSize, source.expectedByteCount - consumed)
      guard let chunk = try source.nextChunk(maxBytes: wanted), !chunk.isEmpty else {
        throw StreamingHashError.sourceShrank(expectedByteCount: source.expectedByteCount)
      }
      hasher.update(data: chunk)
      consumed += chunk.count
    }
    return ArchiveFingerprint(
      sha256Hex: hasher.finalize().map { String(format: "%02x", $0) }.joined(),
      byteSize: consumed
    )
  }
}
