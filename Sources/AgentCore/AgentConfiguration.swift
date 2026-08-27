import Foundation

/// The agent's typed local configuration, document schema version 1.
///
/// Fields map one-to-one onto the JSON configuration document. Loading
/// applies documented defaults when the file does not exist and rejects
/// documents that deviate from the schema instead of guessing. Watched
/// folders are owned by the per-folder preferences registry, not here.
public struct AgentConfiguration: Equatable, Sendable {
  /// Base URL of the Ratatoskr Platform API. Nil while unconfigured.
  public var backendBaseURL: URL?

  /// Largest archive accepted for upload, in bytes.
  public var maxArchiveBytes: Int

  /// Maximum number of simultaneous uploads.
  public var maxConcurrentUploads: Int

  /// Fixed receipt-protocol chunk size used for streamed archive bodies.
  public var uploadChunkBytes: Int

  /// Aggregate queue admission budget, in bytes per scheduler tick.
  public var maxUploadBytesPerSecond: Int

  /// Maximum total bytes the immutable local archive store may hold.
  public var maxArchiveStoreBytes: Int

  /// Documented defaults applied when no configuration file exists: no
  /// backend URL yet, a 2 GiB archive ceiling, and up to two concurrent
  /// uploads.
  /// Documented default store budget applied when the field is absent.
  public static let defaultMaxArchiveStoreBytes = 20 * 1024 * 1024 * 1024
  public static let defaultUploadChunkBytes = 1_048_576
  public static let defaultMaxUploadBytesPerSecond = 8 * 1_048_576
  public static let minimumUploadChunkBytes = 65536
  public static let maximumUploadChunkBytes = 16 * 1_048_576
  public static let maximumUploadBytesPerSecond = 128 * 1_048_576

  public static let defaultValue = AgentConfiguration(
    backendBaseURL: nil,
    maxArchiveBytes: 2 * 1024 * 1024 * 1024,
    maxConcurrentUploads: 2,
    uploadChunkBytes: Self.defaultUploadChunkBytes,
    maxUploadBytesPerSecond: Self.defaultMaxUploadBytesPerSecond,
    maxArchiveStoreBytes: Self.defaultMaxArchiveStoreBytes
  )

  public init(
    backendBaseURL: URL? = nil,
    maxArchiveBytes: Int = 0,
    maxConcurrentUploads: Int = 0,
    uploadChunkBytes: Int = AgentConfiguration.defaultUploadChunkBytes,
    maxUploadBytesPerSecond: Int = AgentConfiguration.defaultMaxUploadBytesPerSecond,
    maxArchiveStoreBytes: Int = 0
  ) {
    self.backendBaseURL = backendBaseURL
    self.maxArchiveBytes = maxArchiveBytes
    self.maxConcurrentUploads = maxConcurrentUploads
    self.uploadChunkBytes = uploadChunkBytes
    self.maxUploadBytesPerSecond = maxUploadBytesPerSecond
    self.maxArchiveStoreBytes = maxArchiveStoreBytes
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
      maxArchiveBytes: document.maxArchiveBytes,
      maxConcurrentUploads: document.maxConcurrentUploads,
      uploadChunkBytes: document.uploadChunkBytes,
      maxUploadBytesPerSecond: document.maxUploadBytesPerSecond,
      maxArchiveStoreBytes: document.maxArchiveStoreBytes
        ?? Self.defaultMaxArchiveStoreBytes
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
