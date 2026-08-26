import Foundation

// Synthetic archive fixtures for classifier tests. Internal on purpose: one
// definition per name across the AgentCoreTests module. Everything here is
// generated in-test; no real personal export ever enters the repository.

/// One stored (uncompressed) entry of a synthetic zip fixture.
struct ZipFixtureEntry {
  let name: String
  let data: Data

  init(name: String, data: Data = Data()) {
    self.name = name
    self.data = data
  }
}

private func littleEndian(_ value: Int, byteCount: Int) -> [UInt8] {
  (0..<byteCount).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
}

private func zipLocalHeader(entry: ZipFixtureEntry, offset: Int) -> [UInt8] {
  let nameBytes = Array(entry.name.utf8)
  var header = Array("PK\u{03}\u{04}".utf8)
  header += littleEndian(20, byteCount: 2)
  header += littleEndian(0, byteCount: 2)
  header += littleEndian(0, byteCount: 2)
  header += littleEndian(0, byteCount: 2)
  header += littleEndian(0, byteCount: 2)
  header += littleEndian(0, byteCount: 4)
  header += littleEndian(entry.data.count, byteCount: 4)
  header += littleEndian(entry.data.count, byteCount: 4)
  header += littleEndian(nameBytes.count, byteCount: 2)
  header += littleEndian(0, byteCount: 2)
  header += nameBytes
  return header
}

private func zipCentralRecord(entry: ZipFixtureEntry, localOffset: Int) -> [UInt8] {
  let nameBytes = Array(entry.name.utf8)
  var record = Array("PK\u{01}\u{02}".utf8)
  record += littleEndian(20, byteCount: 2)  // version made by
  record += littleEndian(20, byteCount: 2)  // version needed
  record += littleEndian(0, byteCount: 2)  // flags
  record += littleEndian(0, byteCount: 2)  // method: stored
  record += littleEndian(0, byteCount: 2)  // mod time
  record += littleEndian(0, byteCount: 2)  // mod date
  record += littleEndian(0, byteCount: 4)  // crc32 (never verified here)
  record += littleEndian(entry.data.count, byteCount: 4)
  record += littleEndian(entry.data.count, byteCount: 4)
  record += littleEndian(nameBytes.count, byteCount: 2)
  record += littleEndian(0, byteCount: 2)  // extra length
  record += littleEndian(0, byteCount: 2)  // comment length
  record += littleEndian(0, byteCount: 2)  // disk start
  record += littleEndian(0, byteCount: 2)  // internal attributes
  record += littleEndian(0, byteCount: 4)  // external attributes
  record += littleEndian(localOffset, byteCount: 4)
  record += nameBytes
  return record
}

/// Builds a stored-method zip whose central directory names exactly the
/// given entries, optionally followed by an archive comment. CRC fields
/// stay zero: shallow classification never reads entry contents, so nothing
/// verifies them.
func makeZipData(entries: [ZipFixtureEntry], comment: Data = Data()) -> Data {
  var body: [UInt8] = []
  var central: [UInt8] = []
  for entry in entries {
    let offset = body.count
    body += zipLocalHeader(entry: entry, offset: offset)
    body += Array(entry.data)
    central += zipCentralRecord(entry: entry, localOffset: offset)
  }
  var eocd = Array("PK\u{05}\u{06}".utf8)
  eocd += littleEndian(0, byteCount: 2)
  eocd += littleEndian(0, byteCount: 2)
  eocd += littleEndian(entries.count, byteCount: 2)
  eocd += littleEndian(entries.count, byteCount: 2)
  eocd += littleEndian(central.count, byteCount: 4)
  eocd += littleEndian(body.count, byteCount: 4)
  eocd += littleEndian(comment.count, byteCount: 2)
  return Data(body + central + eocd + Array(comment))
}

/// Writes bytes into the given directory and returns the file URL.
@discardableResult
func writeClassifierFixture(named name: String, bytes: Data, into directory: URL) throws -> URL {
  let file = directory.appending(path: name)
  try bytes.write(to: file, options: .atomic)
  return file
}
