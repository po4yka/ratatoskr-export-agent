import Foundation

/// The agent's typed local configuration, document schema version 1.
///
/// Fields map one-to-one onto the JSON configuration document. Loading
/// applies documented defaults when the file does not exist and rejects
/// documents that deviate from the schema instead of guessing.
public struct AgentConfiguration: Equatable, Sendable {
  /// Base URL of the Ratatoskr Platform API. Nil while unconfigured.
  public var backendBaseURL: URL?

  /// User-selected folders observed for completed export archives.
  public var watchedFolders: [String]

  /// Largest archive accepted for upload, in bytes.
  public var maxArchiveBytes: Int

  /// Maximum number of simultaneous uploads.
  public var maxConcurrentUploads: Int

  /// Documented defaults applied when no configuration file exists: no
  /// backend URL yet, no watched folders, a 2 GiB archive ceiling, and up
  /// to two concurrent uploads.
  public static let defaultValue = AgentConfiguration(
    backendBaseURL: nil,
    watchedFolders: [],
    maxArchiveBytes: 2 * 1024 * 1024 * 1024,
    maxConcurrentUploads: 2
  )

  public init(
    backendBaseURL: URL? = nil, watchedFolders: [String] = [], maxArchiveBytes: Int = 0,
    maxConcurrentUploads: Int = 0
  ) {
    self.backendBaseURL = backendBaseURL
    self.watchedFolders = watchedFolders
    self.maxArchiveBytes = maxArchiveBytes
    self.maxConcurrentUploads = maxConcurrentUploads
  }

  /// Loads the configuration document at the given file URL.
  ///
  /// A missing file yields the documented defaults rather than an error,
  /// so a fresh installation starts with safe budgets. Present documents
  /// must declare schema version 1 before any other field is read;
  /// further field-level rules land with the following validation pairs.
  public static func load(from fileURL: URL) throws -> AgentConfiguration {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return .defaultValue
    }
    let data = try Data(contentsOf: fileURL)
    let document: RawDocument
    do {
      document = try JSONDecoder().decode(RawDocument.self, from: data)
    } catch let rejection as DocumentRejection {
      throw ConfigurationLoadError(fileURL: fileURL, reason: rejection)
    }
    return AgentConfiguration(
      backendBaseURL: document.backendBaseURL,
      watchedFolders: document.watchedFolders,
      maxArchiveBytes: document.maxArchiveBytes,
      maxConcurrentUploads: document.maxConcurrentUploads
    )
  }
}

public struct ConfigurationLoadError: Error, CustomStringConvertible, Sendable {
  public let fileURL: URL
  let reason: DocumentRejection

  public var description: String {
    "\(fileURL.path): \(reason)"
  }
}

enum DocumentRejection: Error, CustomStringConvertible {
  case unsupportedSchemaVersion(Int?)
  case unknownField(String)
  case insecureBackendEndpoint(String)
  case nonPositiveValue(field: String, value: Int)
  case emptyWatchedFolderEntry(index: Int)

  var description: String {
    switch self {
    case .unsupportedSchemaVersion(.some(let actual)):
      "only schema version 1 is supported, found \(actual)"
    case .unsupportedSchemaVersion(.none):
      "only schema version 1 is supported, none declared"
    case .unknownField(let name):
      "unknown configuration field \"\(name)\""
    case .insecureBackendEndpoint(let endpoint):
      "backend endpoint must use https or plain http on a loopback host, got \(endpoint)"
    case .nonPositiveValue(let field, let value):
      "configuration field \"\(field)\" must be greater than zero, got \(value)"
    case .emptyWatchedFolderEntry(let index):
      "configuration field \"watchedFolders\" must not contain empty entries (first at index \(index))"
    }
  }
}

/// Decode shape enforcing the schema-version gate before any other field
/// is read, so later schema versions never reach field decoding.
private struct RawDocument: Decodable {
  var backendBaseURL: URL?
  var watchedFolders: [String]
  var maxArchiveBytes: Int
  var maxConcurrentUploads: Int

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case backendBaseURL
    case watchedFolders
    case maxArchiveBytes
    case maxConcurrentUploads
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let declaredVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
    guard declaredVersion == 1 else {
      throw DocumentRejection.unsupportedSchemaVersion(declaredVersion)
    }
    let rawContainer = try decoder.container(keyedBy: AnyCodingKey.self)
    let knownFieldNames: Set<String> = [
      CodingKeys.schemaVersion.stringValue,
      CodingKeys.backendBaseURL.stringValue,
      CodingKeys.watchedFolders.stringValue,
      CodingKeys.maxArchiveBytes.stringValue,
      CodingKeys.maxConcurrentUploads.stringValue,
    ]
    if let unexpected = rawContainer.allKeys.first(where: {
      !knownFieldNames.contains($0.stringValue)
    }) {
      throw DocumentRejection.unknownField(unexpected.stringValue)
    }
    backendBaseURL = try container.decodeIfPresent(URL.self, forKey: .backendBaseURL)
    watchedFolders = try container.decode([String].self, forKey: .watchedFolders)
    maxArchiveBytes = try container.decode(Int.self, forKey: .maxArchiveBytes)
    maxConcurrentUploads = try container.decode(Int.self, forKey: .maxConcurrentUploads)
    if maxArchiveBytes <= 0 {
      throw DocumentRejection.nonPositiveValue(field: "maxArchiveBytes", value: maxArchiveBytes)
    }
    if maxConcurrentUploads < 1 {
      throw DocumentRejection.nonPositiveValue(
        field: "maxConcurrentUploads", value: maxConcurrentUploads)
    }
    if let emptyIndex = watchedFolders.firstIndex(where: { $0.isEmpty }) {
      throw DocumentRejection.emptyWatchedFolderEntry(index: emptyIndex)
    }
    if let endpoint = backendBaseURL, !Self.isPermittedBackendEndpoint(endpoint) {
      throw DocumentRejection.insecureBackendEndpoint(endpoint.absoluteString)
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
