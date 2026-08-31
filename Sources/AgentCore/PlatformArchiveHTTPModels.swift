import Foundation

struct PrepareBody: Encodable {
  let sha256: String
  let byteSize: Int
  enum CodingKeys: String, CodingKey {
    case sha256
    case byteSize = "byte_size"
  }
}

struct PrepareResponse: Decodable {
  let operationID: String
  let status: String
  enum CodingKeys: String, CodingKey {
    case operationID = "operation_id"
    case status
  }
}

struct OpenTransferResponse: Decodable {
  let resumptionToken: String
  let chunkSizeBytes: Int
  enum CodingKeys: String, CodingKey {
    case resumptionToken = "resumption_token"
    case chunkSizeBytes = "chunk_size_bytes"
  }
}

struct TransferStatusResponse: Decodable {
  let resumptionToken: String
  let receivedChunks: [Int]
  enum CodingKeys: String, CodingKey {
    case resumptionToken = "resumption_token"
    case receivedChunks = "received_chunks"
  }
}

struct FinalizeRequest: Encodable {
  let resumptionToken: String
  enum CodingKeys: String, CodingKey { case resumptionToken = "resumption_token" }
}

struct PlatformBlobDigest: Decodable {
  let algorithm: String
  let hex: String
}

struct PlatformBlobReference: Decodable {
  let ownerService: String
  let digest: PlatformBlobDigest
  let lengthBytes: Int
  enum CodingKeys: String, CodingKey {
    case ownerService = "owner_service"
    case digest
    case lengthBytes = "length_bytes"
  }
}

struct FinalizeResponse: Decodable {
  let outcome: String
  let blobRef: PlatformBlobReference?
  enum CodingKeys: String, CodingKey {
    case outcome
    case blobRef = "blob_ref"
  }
}
