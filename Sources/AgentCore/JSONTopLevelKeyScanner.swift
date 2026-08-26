import Foundation

/// Collects the top-level keys of a JSON document from a bounded byte
/// prefix, without parsing or retaining any nested content: the keys of the
/// root object, or of the first object inside a root array.
enum JSONTopLevelKeyScanner {
  static let maxPrefixBytes = 65_536
  private static let maxKeys = 64

  /// The observed top-level keys, in first-appearance order. Empty when the
  /// prefix holds no recognizable top-level object.
  static func topLevelKeys(in data: Data) -> [String] {
    var walker = Walker(bytes: Array(data.prefix(maxPrefixBytes)))
    return walker.walk()
  }

  private struct Walker {
    let bytes: [UInt8]
    var position = 0
    var depth = 0
    /// Currently open `{` containers; keys count as top-level at exactly 1.
    var objectDepth = 0
    var keys: [String] = []
    var collecting = true

    init(bytes: [UInt8]) {
      self.bytes = bytes
    }

    mutating func walk() -> [String] {
      skipWhitespace()
      guard peekByte() == UInt8(ascii: "{") || peekByte() == UInt8(ascii: "[") else {
        return []
      }
      while position < bytes.count, collecting {
        step()
      }
      return keys
    }

    private mutating func step() {
      switch bytes[position] {
      case UInt8(ascii: "\""):
        consumeStringAndMaybeRecordKey()
      case UInt8(ascii: "{"):
        objectDepth += 1
        depth += 1
        position += 1
      case UInt8(ascii: "["):
        depth += 1
        position += 1
      case UInt8(ascii: "}"):
        objectDepth -= 1
        depth -= 1
        position += 1
      case UInt8(ascii: "]"):
        depth -= 1
        position += 1
      default:
        position += 1
      }
      if depth == 0 {
        collecting = false
      }
    }

    /// Consumes one string token; records it as a key when it sits at depth
    /// one and is directly followed by a colon.
    private mutating func consumeStringAndMaybeRecordKey() {
      let start = position + 1
      position += 1
      while position < bytes.count {
        if bytes[position] == UInt8(ascii: "\\") {
          position += 2
          continue
        }
        if bytes[position] == UInt8(ascii: "\"") {
          break
        }
        position += 1
      }
      defer {
        position = min(position + 1, bytes.count)
      }
      let key = String(bytes: bytes[start..<position], encoding: .utf8) ?? ""
      if objectDepth == 1, isFollowedByColon(from: position + 1),
        keys.count < JSONTopLevelKeyScanner.maxKeys, !keys.contains(key) {
        keys.append(key)
      }
    }

    private func isFollowedByColon(from start: Int) -> Bool {
      var cursor = start
      while cursor < bytes.count, isWhitespace(bytes[cursor]) {
        cursor += 1
      }
      return cursor < bytes.count && bytes[cursor] == UInt8(ascii: ":")
    }

    private func peekByte() -> UInt8 {
      position < bytes.count ? bytes[position] : 0
    }

    private mutating func skipWhitespace() {
      while position < bytes.count, isWhitespace(bytes[position]) {
        position += 1
      }
    }

    private func isWhitespace(_ byte: UInt8) -> Bool {
      byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\n")
        || byte == UInt8(ascii: "\r")
    }
  }
}
