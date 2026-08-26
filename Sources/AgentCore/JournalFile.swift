import CryptoKit
import Foundation

enum JournalRecordKind: String, Codable {
  case transition
  case recovery
  case snapshot
}

struct JournalRecord: Codable {
  let kind: JournalRecordKind
  let entry: JournalEntry?
  let entries: [JournalEntry]?

  static func transition(_ entry: JournalEntry) -> JournalRecord {
    JournalRecord(kind: .transition, entry: entry, entries: nil)
  }

  static func recovery(_ entry: JournalEntry) -> JournalRecord {
    JournalRecord(kind: .recovery, entry: entry, entries: nil)
  }

  static func snapshot(_ entries: [JournalEntry]) -> JournalRecord {
    JournalRecord(kind: .snapshot, entry: nil, entries: entries)
  }
}

private struct JournalEnvelope: Codable {
  let checksum: String
  let payloadBase64: String
}

enum JournalFile {
  static func append(_ record: JournalRecord, to url: URL) throws {
    let line = try encodedLine(for: record)
    if !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(
        atPath: url.path,
        contents: nil,
        attributes: [.posixPermissions: 0o600]
      )
    }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: line)
    try handle.synchronize()
  }

  static func readProjection(at url: URL) throws -> [UUID: JournalEntry] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
    let data = try Data(contentsOf: url)
    guard data.isEmpty || data.last == 10 else {
      throw LocalJournalError.safeStop(.missingTrailingNewline)
    }
    var projection: [UUID: JournalEntry] = [:]
    for line in try lines(in: data) {
      do {
        try apply(try decodedRecord(from: line), to: &projection)
      } catch let error as LocalJournalError {
        throw error
      } catch {
        throw LocalJournalError.safeStop(.malformedRecord)
      }
    }
    return projection
  }

  static func encodedLine(for record: JournalRecord) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let payload = try encoder.encode(record)
    let envelope = JournalEnvelope(
      checksum: checksum(for: payload),
      payloadBase64: payload.base64EncodedString()
    )
    return try encoder.encode(envelope) + Data([10])
  }

  private static func decodedRecord(from line: Data) throws -> JournalRecord {
    let envelope: JournalEnvelope
    do {
      envelope = try JSONDecoder().decode(JournalEnvelope.self, from: line)
    } catch {
      throw LocalJournalError.safeStop(.malformedRecord)
    }
    guard let payload = Data(base64Encoded: envelope.payloadBase64),
      checksum(for: payload) == envelope.checksum else {
      throw LocalJournalError.safeStop(.checksumMismatch)
    }
    do {
      return try JSONDecoder().decode(JournalRecord.self, from: payload)
    } catch {
      throw LocalJournalError.safeStop(.malformedRecord)
    }
  }

  private static func apply(_ record: JournalRecord, to projection: inout [UUID: JournalEntry]) throws {
    if record.kind == .snapshot {
      return try applySnapshot(record, to: &projection)
    }
    guard let entry = record.entry, record.entries == nil, JournalIdentity.matches(entry) else {
      throw LocalJournalError.safeStop(.impossibleTransition)
    }
    guard let previous = projection[entry.id] else {
      guard record.kind == .transition, entry.state == .discovered,
        !projection.values.contains(where: { $0.fingerprint == entry.fingerprint }) else {
        throw LocalJournalError.safeStop(.impossibleTransition)
      }
      projection[entry.id] = entry
      return
    }
    let keepsIdentity = previous.fingerprint == entry.fingerprint &&
      previous.idempotencyKey == entry.idempotencyKey
    let normalTransition = record.kind == .transition &&
      previous.state.allowsTransition(toward: entry.state)
    let recoveryTransition = record.kind == .recovery && previous.state == .uploading &&
      entry.state == .queued
    guard keepsIdentity && (normalTransition || recoveryTransition) else {
      throw LocalJournalError.safeStop(.impossibleTransition)
    }
    projection[entry.id] = entry
  }

  private static func applySnapshot(_ record: JournalRecord, to projection: inout [UUID: JournalEntry]) throws {
    guard projection.isEmpty, record.entry == nil, let entries = record.entries else {
      throw LocalJournalError.safeStop(.impossibleTransition)
    }
    for entry in entries {
      guard JournalIdentity.matches(entry), projection[entry.id] == nil,
        !projection.values.contains(where: { $0.fingerprint == entry.fingerprint }) else {
        throw LocalJournalError.safeStop(.impossibleTransition)
      }
      projection[entry.id] = entry
    }
  }

  private static func lines(in data: Data) throws -> [Data] {
    let bytes = [UInt8](data)
    var start = 0
    var lines: [Data] = []
    for index in bytes.indices where bytes[index] == 10 {
      guard start < index else {
        throw LocalJournalError.safeStop(.malformedRecord)
      }
      lines.append(Data(bytes[start..<index]))
      start = index + 1
    }
    return lines
  }

  private static func checksum(for data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
