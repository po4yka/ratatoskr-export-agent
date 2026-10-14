import Foundation

/// The shared blob-transfer contract on `/v1/notes/connections/{id}/blobs`.
/// Notes keys no upload by an idempotency key, so the key is not sent.
struct NotesBlobTransport: BlobReceiptTransport {
  let http: any NotesChannelHTTP
  let connectionID: String

  private var base: String { "v1/notes/connections/\(connectionID)/blobs" }

  func open(_ declaration: BlobUploadDeclaration, idempotencyKey _: String) async throws -> BlobUploadSession {
    let answer = try await call(
      "POST", base, body: try JSONEncoder().encode(declaration), type: "application/json", accepting: [200, 201]
    )
    let body = try decodeNotesAnswer(OpenTransferResponse.self, from: answer)
    guard !body.resumptionToken.isEmpty, body.chunkSizeBytes > 0 else {
      throw NotesChannelError.invalidAnswer
    }
    return BlobUploadSession(token: body.resumptionToken, chunkSizeBytes: body.chunkSizeBytes)
  }

  func status(token: String) async throws -> BlobUploadStatus {
    let answer = try await call("GET", "\(base)/\(token)/status", accepting: [200])
    let body = try decodeNotesAnswer(TransferStatusResponse.self, from: answer)
    guard body.resumptionToken == token else {
      throw NotesChannelError.invalidAnswer
    }
    return BlobUploadStatus(receivedIndices: Set(body.receivedChunks))
  }

  func send(token: String, index: Int, bytes: Data) async throws {
    _ = try await call(
      "PUT", "\(base)/\(token)/chunks/\(index)", body: bytes, type: "application/octet-stream", accepting: [200, 204]
    )
  }

  func finalize(token: String) async throws -> BlobStoredReceipt {
    let answer = try await call(
      "POST", "\(base)/\(token)/finalize",
      body: try JSONEncoder().encode(FinalizeRequest(resumptionToken: token)), type: "application/json", accepting: [200]
    )
    let body = try decodeNotesAnswer(FinalizeResponse.self, from: answer)
    guard body.outcome == "stored", let blob = body.blobRef, blob.digest.algorithm == "sha256" else {
      throw BlobReceiptTransportError.invalidReceipt
    }
    return BlobStoredReceipt(
      sha256Hex: blob.digest.hex, byteSize: blob.lengthBytes, reference: "\(blob.ownerService):sha256:\(blob.digest.hex)"
    )
  }

  /// A `404` of a session that notes forgot is an expired session; a `404` of
  /// the connection is `connectionGone`.
  private func call(
    _ method: String, _ path: String, body: Data? = nil, type: String? = nil, accepting: Set<Int>
  ) async throws -> NotesChannelAnswer {
    let answer = try await http.perform(NotesChannelRequest(method: method, path: path, body: body, contentType: type))
    guard accepting.contains(answer.status) else {
      let error = NotesFault.error(of: answer)
      if answer.status == 404, error != .connectionGone {
        throw BlobReceiptTransportError.expiredSession
      }
      throw error
    }
    return answer
  }
}
