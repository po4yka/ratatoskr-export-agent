import CryptoKit
import XCTest
@testable import AgentCore

/// Scripts a source that reports more bytes than it ever serves, so the
/// short-read failure path runs deterministically without real files.
private struct TruncatingSource: ArchiveChunkSourcing {
  let expectedByteCount = 200
  var chunksServed = 0

  mutating func nextChunk(maxBytes: Int) throws -> Data? {
    chunksServed += 1
    if chunksServed <= 2 {
      return Data(repeating: 0xAB, count: maxBytes)
    }
    return nil
  }
}

final class StreamingHasherTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
      create: true
    )
  }

  override func tearDown() {
    if let directory {
      try? FileManager.default.removeItem(at: directory)
    }
  }

  func testEmptyFileYieldsKnownEmptyDigest() throws {
    let file = try writeFixture(named: "empty.bin", bytes: Data())

    let fingerprint = try StreamingHasher(chunkSize: 64).fingerprint(at: file)

    XCTAssertEqual(
      fingerprint.sha256Hex,
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "a zero-byte input must produce the published empty-string SHA-256")
    XCTAssertEqual(fingerprint.byteSize, 0, "the hashed size of an empty file is zero")
  }

  func testShortInputMatchesPublishedVector() throws {
    let file = try writeFixture(named: "abc.bin", bytes: Data("abc".utf8))

    let fingerprint = try StreamingHasher(chunkSize: 64).fingerprint(at: file)

    XCTAssertEqual(
      fingerprint.sha256Hex,
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      "the published abc vector pins algorithm correctness")
    XCTAssertEqual(fingerprint.byteSize, 3, "the hashed size counts exactly the bytes read")
  }

  func testChunkedFixtureWritesHashCorrectly() throws {
    let logical = Data((0..<5_000).map { UInt8(truncatingIfNeeded: ($0 &* 31) &+ 7) })
    let file = directory.appending(path: "chunked.bin")
    FileManager.default.createFile(atPath: file.path, contents: nil)
    let handle = try FileHandle(forWritingTo: file)
    defer {
      try? handle.close()
    }
    var offset = 0
    while offset < logical.count {
      let end = min(offset + 17, logical.count)
      try handle.write(contentsOf: logical.subdata(in: offset..<end))
      offset = end
    }

    let fingerprint = try StreamingHasher(chunkSize: 64).fingerprint(at: file)

    let expected = SHA256.hash(data: logical).map { String(format: "%02x", $0) }.joined()
    XCTAssertEqual(
      fingerprint.sha256Hex, expected,
      "content written through many separate appends must hash to the whole-content digest")
    XCTAssertEqual(fingerprint.byteSize, logical.count, "size must equal the on-disk byte count")
  }

  func testShrinkingSourceFailsWithoutDigest() throws {
    let hasher = StreamingHasher(chunkSize: 64)

    XCTAssertThrowsError(try hasher.fingerprint(source: TruncatingSource())) { error in
      XCTAssertEqual(
        error as? StreamingHashError,
        .sourceShrank(expectedByteCount: 200),
        "a source that ends early must fail naming its expected size instead of yielding a digest")
    }
  }

  func testHashingLeavesSourceUntouched() throws {
    let content = Data((0..<600).map { UInt8(truncatingIfNeeded: $0 &* 7) })
    let file = try writeFixture(named: "source.bin", bytes: content)
    let attributesBefore = try FileManager.default.attributesOfItem(atPath: file.path)

    _ = try StreamingHasher(chunkSize: 64).fingerprint(at: file)

    let attributesAfter = try FileManager.default.attributesOfItem(atPath: file.path)
    XCTAssertEqual(
      (attributesAfter[.size] as? NSNumber)?.int64Value,
      (attributesBefore[.size] as? NSNumber)?.int64Value,
      "hashing must not change the source size")
    XCTAssertEqual(
      (attributesAfter[.modificationDate] as? Date),
      (attributesBefore[.modificationDate] as? Date),
      "hashing must not touch the source modification time")
    XCTAssertEqual(
      try Data(contentsOf: file), content, "hashing must not alter the source bytes")
  }

  @discardableResult
  private func writeFixture(named name: String, bytes: Data) throws -> URL {
    let file = directory.appending(path: name)
    try bytes.write(to: file, options: .atomic)
    return file
  }
}
