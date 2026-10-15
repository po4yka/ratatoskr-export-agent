import Foundation
import os

/// Keeps the results that notes did not take yet, by connection and
/// operation id, so that a restart sends them again in place of a new apply.
public protocol DeviceResultStoring: Sendable {
  func load(connectionID: String) async throws -> [String: Data]
  func save(_ results: [String: Data], connectionID: String) async throws
}

/// One JSON file, `{"connections":{"<connection id>":{"<operation id>":
/// "<base64 result body>"}}}`. A result body names the paths of the
/// operation, so only the owner reads the file: it is written through a
/// temporary file created `0600` and renamed, and its folder is `0700`. A
/// file that does not decode is moved to `<name>.corrupt-<seconds>` with one
/// log line, and the store starts empty. Any other read error throws, so a
/// caller keeps what it holds and loads again later.
public actor FileDeviceResultStore: DeviceResultStoring {
  private struct Document: Codable {
    var connections: [String: [String: Data]]
  }

  private let fileURL: URL
  private let now: @Sendable () -> Date
  private let log: @Sendable (String) -> Void

  public init(
    fileURL: URL,
    now: @escaping @Sendable () -> Date = { Date() },
    log: @escaping @Sendable (String) -> Void = { line in
      Logger(subsystem: "ratatoskr.export-agent", category: "device-results").error("\(line, privacy: .public)")
    }
  ) {
    self.fileURL = fileURL
    self.now = now
    self.log = log
  }

  public func load(connectionID: String) async throws -> [String: Data] {
    try document().connections[connectionID] ?? [:]
  }

  public func save(_ results: [String: Data], connectionID: String) async throws {
    var document = try document()
    document.connections[connectionID] = results.isEmpty ? nil : results
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try write(try encoder.encode(document))
  }

  private func document() throws -> Document {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return Document(connections: [:])
    }
    let data = try Data(contentsOf: fileURL)
    do {
      return try JSONDecoder().decode(Document.self, from: data)
    } catch {
      let aside = fileURL.deletingLastPathComponent()
        .appendingPathComponent("\(fileURL.lastPathComponent).corrupt-\(Int(now().timeIntervalSince1970))")
      try FileManager.default.moveItem(at: fileURL, to: aside)
      log("The kept device results did not decode; they were moved to \(aside.lastPathComponent), and the store starts empty.")
      return Document(connections: [:])
    }
  }

  private func write(_ data: Data) throws {
    let folder = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
    let temporary = folder.appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
    let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
    guard descriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    do {
      try handle.write(contentsOf: data)
      try handle.synchronize()
      try handle.close()
      guard rename(temporary.path, fileURL.path) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
    } catch {
      try? FileManager.default.removeItem(at: temporary)
      throw error
    }
  }
}
