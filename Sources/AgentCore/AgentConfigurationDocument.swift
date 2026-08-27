import Foundation

/// Decode shape enforcing the schema-version gate before any other field is read.
struct RawDocument: Decodable {
  var backendBaseURL: URL?
  var maxArchiveBytes: Int
  var maxConcurrentUploads: Int
  var uploadChunkBytes: Int
  var maxUploadBytesPerSecond: Int
  var maxArchiveStoreBytes: Int?

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion
    case backendBaseURL
    case maxArchiveBytes
    case maxConcurrentUploads
    case uploadChunkBytes
    case maxUploadBytesPerSecond
    case maxArchiveStoreBytes
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let declaredVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
    guard declaredVersion == 1 else {
      throw DocumentRejection.unsupportedSchemaVersion(declaredVersion)
    }
    try Self.rejectUnknownFields(in: decoder)
    backendBaseURL = try container.decodeIfPresent(URL.self, forKey: .backendBaseURL)
    maxArchiveBytes = try container.decode(Int.self, forKey: .maxArchiveBytes)
    maxConcurrentUploads = try container.decode(Int.self, forKey: .maxConcurrentUploads)
    uploadChunkBytes = try container.decode(Int.self, forKey: .uploadChunkBytes)
    maxUploadBytesPerSecond = try container.decode(Int.self, forKey: .maxUploadBytesPerSecond)
    maxArchiveStoreBytes = try container.decodeIfPresent(Int.self, forKey: .maxArchiveStoreBytes)
    try validateBudgets()
    if let endpoint = backendBaseURL, !Self.isPermittedBackendEndpoint(endpoint) {
      throw DocumentRejection.insecureBackendEndpoint(endpoint.absoluteString)
    }
  }

  private static func rejectUnknownFields(in decoder: Decoder) throws {
    let rawContainer = try decoder.container(keyedBy: AnyCodingKey.self)
    let known = Set(CodingKeys.allCases.map(\.stringValue))
    if let unexpected = rawContainer.allKeys.first(where: { !known.contains($0.stringValue) }) {
      throw DocumentRejection.unknownField(unexpected.stringValue)
    }
  }

  private func validateBudgets() throws {
    try Self.requirePositive(maxArchiveBytes, name: "maxArchiveBytes")
    try Self.requirePositive(maxConcurrentUploads, name: "maxConcurrentUploads")
    try Self.requireRange(
      uploadChunkBytes,
      name: "uploadChunkBytes",
      minimum: AgentConfiguration.minimumUploadChunkBytes,
      maximum: AgentConfiguration.maximumUploadChunkBytes
    )
    try Self.requireRange(
      maxUploadBytesPerSecond,
      name: "maxUploadBytesPerSecond",
      minimum: 1,
      maximum: AgentConfiguration.maximumUploadBytesPerSecond
    )
    guard maxUploadBytesPerSecond >= uploadChunkBytes else {
      throw DocumentRejection.incompatibleTransferCaps(
        chunkBytes: uploadChunkBytes,
        bytesPerSecond: maxUploadBytesPerSecond
      )
    }
    try Self.requirePositive(
      maxArchiveStoreBytes ?? AgentConfiguration.defaultMaxArchiveStoreBytes,
      name: "maxArchiveStoreBytes"
    )
  }

  private static func requirePositive(_ value: Int, name: String) throws {
    guard value > 0 else {
      throw DocumentRejection.nonPositiveValue(field: name, value: value)
    }
  }

  private static func requireRange(
    _ value: Int,
    name: String,
    minimum: Int,
    maximum: Int
  ) throws {
    guard value >= minimum, value <= maximum else {
      throw DocumentRejection.outOfRangeValue(
        field: name, value: value, minimum: minimum, maximum: maximum
      )
    }
  }

  private static func isPermittedBackendEndpoint(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
      return false
    }
    if scheme == "https" {
      return true
    }
    var host = url.host ?? ""
    if host.hasPrefix("["), host.hasSuffix("]"), host.count >= 2 {
      host = String(host.dropFirst().dropLast())
    }
    return host == "localhost" || host == "127.0.0.1" || host == "::1"
  }
}

private struct AnyCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int?

  init?(stringValue: String) {
    self.stringValue = stringValue
    intValue = nil
  }

  init?(intValue: Int) {
    stringValue = String(intValue)
    self.intValue = intValue
  }
}
