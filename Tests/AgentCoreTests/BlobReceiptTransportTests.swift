import AgentCore
import CryptoKit
import Foundation
import XCTest

final class BlobReceiptTransportTests: XCTestCase {
  func testOpenDeclarationPrecedesPayload() async throws {
    let bytes = Data(repeating: 9, count: 70000)
    let fingerprint = ArchiveFingerprint(sha256Hex: digest(bytes), byteSize: bytes.count)
    let archiveURL = try write(bytes)
    let server = BlobReceiptHarnessServer(fingerprint: fingerprint)

    _ = try await ResumableArchiveUploader(chunkSize: 65536).upload(
      archiveURL: archiveURL,
      fingerprint: fingerprint,
      mediaType: "application/zip",
      idempotencyKey: "ratatoskr-export-agent/sha256/\(fingerprint.sha256Hex)",
      transport: server
    )

    let events = await server.events
    let recordedDeclaration = await server.declaration
    let recordedIdempotencyKey = await server.idempotencyKey
    let declaration = try XCTUnwrap(recordedDeclaration)
    XCTAssertEqual(events.first, "open")
    XCTAssertEqual(events.dropFirst().first, "status")
    XCTAssertEqual(declaration.digest.algorithm, "sha256")
    XCTAssertEqual(declaration.digest.hex, fingerprint.sha256Hex)
    XCTAssertEqual(declaration.declaredSizeBytes, bytes.count)
    XCTAssertEqual(declaration.chunkSizeBytes, 65536)
    XCTAssertEqual(recordedIdempotencyKey, "ratatoskr-export-agent/sha256/\(fingerprint.sha256Hex)")
  }

  func testStoredReceiptMustMatchLocalFingerprint() async throws {
    let bytes = Data(repeating: 5, count: 1)
    let fingerprint = ArchiveFingerprint(sha256Hex: digest(bytes), byteSize: bytes.count)
    let archiveURL = try write(bytes)
    let server = BlobReceiptHarnessServer(
      fingerprint: fingerprint,
      finalReceipt: BlobStoredReceipt(sha256Hex: String(repeating: "0", count: 64), byteSize: 1, reference: "bad")
    )

    do {
      _ = try await ResumableArchiveUploader(chunkSize: 65536).upload(
        archiveURL: archiveURL,
        fingerprint: fingerprint,
        mediaType: "application/zip",
        idempotencyKey: "key",
        transport: server
      )
      XCTFail("expected mismatched receipt to be refused")
    } catch BlobReceiptTransportError.invalidReceipt {
      // Expected: local digest remains authoritative.
    }
  }

  private func write(_ bytes: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "receipt-\(UUID().uuidString)")
    try bytes.write(to: url)
    return url
  }

  private func digest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}

private actor BlobReceiptHarnessServer: BlobReceiptTransport {
  let fingerprint: ArchiveFingerprint
  let finalReceipt: BlobStoredReceipt?
  var events = [String]()
  var declaration: BlobUploadDeclaration?
  var idempotencyKey: String?
  var received = Set<Int>()

  init(fingerprint: ArchiveFingerprint, finalReceipt: BlobStoredReceipt? = nil) {
    self.fingerprint = fingerprint
    self.finalReceipt = finalReceipt
  }

  func open(_ declaration: BlobUploadDeclaration, idempotencyKey: String) async throws -> BlobUploadSession {
    events.append("open")
    self.declaration = declaration
    self.idempotencyKey = idempotencyKey
    return BlobUploadSession(token: "harness-session", chunkSizeBytes: declaration.chunkSizeBytes)
  }

  func status(token _: String) async throws -> BlobUploadStatus {
    events.append("status")
    return BlobUploadStatus(receivedIndices: received)
  }

  func send(token _: String, index: Int, bytes _: Data) async throws {
    events.append("send:\(index)")
    received.insert(index)
  }

  func finalize(token _: String) async throws -> BlobStoredReceipt {
    events.append("finalize")
    return finalReceipt ?? BlobStoredReceipt(
      sha256Hex: fingerprint.sha256Hex,
      byteSize: fingerprint.byteSize,
      reference: "harness"
    )
  }
}
