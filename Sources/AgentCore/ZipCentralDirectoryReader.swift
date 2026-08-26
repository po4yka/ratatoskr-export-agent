import Foundation

/// The outcome of a bounded central-directory read: whether the directory
/// was located inside the scan window and the entry names it listed.
struct ZipCentralDirectoryListing: Equatable, Sendable {
  /// False when no End-of-Central-Directory record was found in the window.
  let foundDirectory: Bool

  let entryNames: [String]

  static func notFound() -> ZipCentralDirectoryListing {
    ZipCentralDirectoryListing(foundDirectory: false, entryNames: [])
  }
}

/// Reads zip central-directory entry names without ever decompressing entry
/// contents. Every read is bounded: the EOCD is located within a trailing
/// window, and the directory listing stops at fixed entry/byte caps.
enum ZipCentralDirectoryReader {
  private static let eocdSignature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
  private static let centralSignature: [UInt8] = [0x50, 0x4B, 0x01, 0x02]
  private static let eocdMinimumLength = 22
  private static let windowSize = 65_536
  private static let maxEntries = 65_536
  private static let maxDirectoryBytes = 8 * 1_048_576

  static func listing(ofFileAt url: URL, fileSize: Int) throws -> ZipCentralDirectoryListing {
    guard fileSize >= eocdMinimumLength else {
      return .notFound()
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer {
      try? handle.close()
    }
    let tailStart = max(0, fileSize - windowSize)
    let tail = try handle.readChunk(
      fromAbsoluteOffset: UInt64(tailStart), count: fileSize - tailStart)
    guard let cursor = locateEOCD(in: tail) else {
      return .notFound()
    }
    let entryCount = Int(readLE16(tail, at: cursor + 10))
    let directorySize = Int(readLE32(tail, at: cursor + 12))
    let directoryOffset = Int(readLE32(tail, at: cursor + 16))
    guard directoryOffset >= 0, directorySize >= 0,
      directoryOffset <= fileSize, directorySize <= maxDirectoryBytes,
      entryCount > 0
    else {
      return .notFound()
    }
    let directory = try handle.readChunk(
      fromAbsoluteOffset: UInt64(directoryOffset),
      count: min(directorySize, maxDirectoryBytes)
    )
    return parseNames(from: directory, expectedEntries: entryCount)
  }

  /// Scans the tail backwards for the EOCD signature.
  private static func locateEOCD(in tail: [UInt8]) -> Int? {
    guard tail.count >= eocdMinimumLength else {
      return nil
    }
    for start in stride(from: tail.count - eocdMinimumLength, through: 0, by: -1)
    where tail[start] == eocdSignature[0] {
      if Array(tail[start..<min(start + 4, tail.count)]) == eocdSignature {
        return start
      }
    }
    return nil
  }

  private static func parseNames(
    from directory: [UInt8],
    expectedEntries: Int
  ) -> ZipCentralDirectoryListing {
    var names: [String] = []
    var offset = 0
    while names.count < min(expectedEntries, maxEntries), offset + 46 <= directory.count {
      guard Array(directory[offset..<offset + 4]) == centralSignature else {
        break
      }
      let nameLength = Int(readLE16(directory, at: offset + 28))
      let extraLength = Int(readLE16(directory, at: offset + 30))
      let commentLength = Int(readLE16(directory, at: offset + 32))
      let nameEnd = offset + 46 + nameLength
      guard nameEnd + extraLength + commentLength <= directory.count else {
        break
      }
      let name = String(bytes: directory[(offset + 46)..<nameEnd], encoding: .utf8) ?? ""
      names.append(name)
      offset = nameEnd + extraLength + commentLength
    }
    return ZipCentralDirectoryListing(foundDirectory: true, entryNames: names)
  }

  private static func readLE16(_ bytes: [UInt8], at offset: Int) -> Int {
    Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
  }

  private static func readLE32(_ bytes: [UInt8], at offset: Int) -> Int {
    readLE16(bytes, at: offset) | (readLE16(bytes, at: offset + 2) << 16)
  }
}

extension FileHandle {
  fileprivate func readChunk(fromAbsoluteOffset offset: UInt64, count: Int) throws -> [UInt8] {
    try seek(toOffset: offset)
    return (try read(upToCount: count)).map(Array.init) ?? []
  }
}
