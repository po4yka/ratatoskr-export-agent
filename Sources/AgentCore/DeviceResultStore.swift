import Foundation

/// Keeps the results that notes did not take yet, by connection and
/// operation id, so that a restart sends them again in place of a new apply.
public protocol DeviceResultStoring: Sendable {
  func load(connectionID: String) async throws -> [String: Data]
  func save(_ results: [String: Data], connectionID: String) async throws
}

/// One JSON file, `{"connections":{"<connection id>":{"<operation id>":
/// "<base64 result body>"}}}`, written atomically. A result body names the
/// paths of the operation, so the file stays in the support directory of the
/// agent. A file that does not decode is read as empty and written again.
public actor FileDeviceResultStore: DeviceResultStoring {
  private struct Document: Codable {
    var connections: [String: [String: Data]]
  }

  private let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load(connectionID: String) async throws -> [String: Data] {
    document().connections[connectionID] ?? [:]
  }

  public func save(_ results: [String: Data], connectionID: String) async throws {
    var document = document()
    document.connections[connectionID] = results.isEmpty ? nil : results
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(document).write(to: fileURL, options: .atomic)
  }

  private func document() -> Document {
    guard let data = try? Data(contentsOf: fileURL), let document = try? JSONDecoder().decode(Document.self, from: data) else {
      return Document(connections: [:])
    }
    return document
  }
}
