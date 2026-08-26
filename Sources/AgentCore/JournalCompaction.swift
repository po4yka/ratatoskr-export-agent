import Darwin
import Foundation

extension JournalFile {
  static func compact(
    _ projection: [UUID: JournalEntry],
    at url: URL,
    maximumBytes: Int
  ) throws {
    let currentSize = try fileSize(at: url)
    guard currentSize > maximumBytes else { return }
    let entries = projection.values.sorted { $0.id.uuidString < $1.id.uuidString }
    let snapshot = try encodedLine(for: .snapshot(entries))
    guard snapshot.count <= maximumBytes else { return }
    let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(
      ".ratatoskr-journal-tmp-\(UUID().uuidString)"
    )
    try writeSynchronously(snapshot, to: temporaryURL)
    do {
      guard rename(temporaryURL.path, url.path) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
    } catch {
      try? FileManager.default.removeItem(at: temporaryURL)
      throw error
    }
  }

  private static func fileSize(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.size] as? NSNumber)?.intValue ?? 0
  }

  private static func writeSynchronously(_ data: Data, to url: URL) throws {
    FileManager.default.createFile(
      atPath: url.path,
      contents: nil,
      attributes: [.posixPermissions: 0o600]
    )
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.write(contentsOf: data)
    try handle.synchronize()
  }
}
