import AgentCore
import Foundation

actor PermanentFailureTransport: BlobReceiptTransport {
  var openCount = 0

  func open(_: BlobUploadDeclaration, idempotencyKey _: String) async throws -> BlobUploadSession {
    openCount += 1
    throw BlobReceiptTransportError.permanent
  }

  func status(token _: String) async throws -> BlobUploadStatus {
    fatalError("unreachable")
  }

  func send(token _: String, index _: Int, bytes _: Data) async throws {
    fatalError("unreachable")
  }

  func finalize(token _: String) async throws -> BlobStoredReceipt {
    fatalError("unreachable")
  }
}
