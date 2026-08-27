import AgentCore
import CryptoKit
import Foundation
import XCTest

final class ResumableUploadTests: XCTestCase {
  func testResumesOnlyMissingChunksAfterBoundaryInterruption() async throws {
    let bytes = Data((0 ..< 150_000).map { UInt8($0 % 251) })
    let archive = try write(bytes)
    let fingerprint = ArchiveFingerprint(sha256Hex: digest(bytes), byteSize: bytes.count)
    let harness = ReceiptHarness(fingerprint: fingerprint, failAfterRecording: 1)
    let uploader = ResumableArchiveUploader(chunkSize: 65536)

    do {
      _ = try await uploader.upload(
        archiveURL: archive,
        fingerprint: fingerprint,
        mediaType: "application/zip",
        idempotencyKey: "key",
        transport: harness
      )
      XCTFail("expected interruption")
    } catch BlobReceiptTransportError.unavailable {}

    _ = try await uploader.upload(
      archiveURL: archive,
      fingerprint: fingerprint,
      mediaType: "application/zip",
      idempotencyKey: "key",
      checkpoint: BlobUploadSession(token: harness.token, chunkSizeBytes: 65536),
      transport: harness
    )

    let sentIndices = await harness.sentIndices
    let statusReads = await harness.statusReads
    XCTAssertEqual(sentIndices, [0, 1, 2])
    XCTAssertGreaterThanOrEqual(statusReads, 2)
  }

  func testRetryAfterLostFinalizeAcknowledgementCreatesOneReceipt() async throws {
    let bytes = Data(repeating: 7, count: 70000)
    let archive = try write(bytes)
    let fingerprint = ArchiveFingerprint(sha256Hex: digest(bytes), byteSize: bytes.count)
    let harness = ReceiptHarness(fingerprint: fingerprint, loseFirstFinalizeAcknowledgement: true)
    let uploader = ResumableArchiveUploader(chunkSize: 65536)
    do {
      _ = try await uploader.upload(
        archiveURL: archive,
        fingerprint: fingerprint,
        mediaType: "application/zip",
        idempotencyKey: "key",
        transport: harness
      )
      XCTFail("expected lost acknowledgement")
    } catch BlobReceiptTransportError.unavailable {}
    _ = try await uploader.upload(
      archiveURL: archive,
      fingerprint: fingerprint,
      mediaType: "application/zip",
      idempotencyKey: "key",
      checkpoint: BlobUploadSession(token: harness.token, chunkSizeBytes: 65536),
      transport: harness
    )
    let createdReceipts = await harness.createdReceipts
    XCTAssertEqual(createdReceipts, 1)
  }

  private func write(_ data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "upload-\(UUID().uuidString)")
    try data.write(to: url)
    return url
  }

  private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

private actor ReceiptHarness: BlobReceiptTransport {
  let fingerprint: ArchiveFingerprint
  let failAfterRecording: Int?
  let loseFirstFinalizeAcknowledgement: Bool
  let token = "rst_fixture"
  var received = Set<Int>()
  var sentIndices = [Int]()
  var statusReads = 0
  var didFail = false
  var didLoseFinalize = false
  var createdReceipts = 0
  init(fingerprint: ArchiveFingerprint, failAfterRecording: Int? = nil, loseFirstFinalizeAcknowledgement: Bool = false) {
    self.fingerprint = fingerprint
    self.failAfterRecording = failAfterRecording
    self.loseFirstFinalizeAcknowledgement = loseFirstFinalizeAcknowledgement
  }

  func open(_ declaration: BlobUploadDeclaration, idempotencyKey _: String) async throws -> BlobUploadSession {
    BlobUploadSession(token: token, chunkSizeBytes: declaration.chunkSizeBytes)
  }

  func status(token _: String) async throws -> BlobUploadStatus {
    statusReads += 1
    return BlobUploadStatus(receivedIndices: received)
  }

  func send(token _: String, index: Int, bytes _: Data) async throws {
    received.insert(index)
    sentIndices.append(index)
    if index == failAfterRecording, !didFail {
      didFail = true
      throw BlobReceiptTransportError.unavailable
    }
  }

  func finalize(token _: String) async throws -> BlobStoredReceipt {
    if createdReceipts == 0 {
      createdReceipts = 1
    }
    if loseFirstFinalizeAcknowledgement && !didLoseFinalize {
      didLoseFinalize = true
      throw BlobReceiptTransportError.unavailable
    }
    return BlobStoredReceipt(
      sha256Hex: fingerprint.sha256Hex,
      byteSize: fingerprint.byteSize,
      reference: "blob"
    )
  }
}
