import CryptoKit
import Foundation

extension ObsidianCLIApply {
  /// A `create` with no base that finds an empty file at its path: the file
  /// of its own `obsidian create` in an earlier pass whose write did not
  /// happen (a time-out, or a failed write). The agent writes the bytes and
  /// does not run the CLI again. Nil for any other operation.
  func finishedCreate(
    _ operation: DeviceOperation, local: String?, source: URL, content: @Sendable () async throws -> Data
  ) async throws -> DeviceOperationOutcome? {
    guard operation.kind == "create", operation.baseHash == nil, local == NotesBlobFile.emptySHA256 else {
      return nil
    }
    try files.write(try verified(try await content(), operation), to: source)
    return .applied(sha256: try files.sha256(at: source))
  }

  /// The hash of the file after the operation. Obsidian can write the
  /// frontmatter of a `set_property` after the CLI returned, so a file that
  /// still has the base hash is read once more after `settle`.
  func resultHash(_ operation: DeviceOperation, at target: URL) async throws -> String? {
    let hash = try files.sha256(at: target)
    guard operation.kind == "set_property", hash == operation.baseHash else {
      return hash
    }
    await settle()
    return try files.sha256(at: target)
  }

  /// Makes the change of the operation. Nil when the vault has it.
  func change(
    _ operation: DeviceOperation, source: URL, target: URL, content: @Sendable () async throws -> Data
  ) async throws -> DeviceOperationOutcome? {
    switch operation.kind {
    case "update":
      try files.write(try await verified(content(), operation), to: source)
      return nil
    case "create":
      let bytes = try await verified(content(), operation)
      if let refused = await run(["create", "path=\(operation.path)"], expecting: { FileManager.default.fileExists(atPath: source.path) }) {
        return refused
      }
      try files.write(bytes, to: source)
      return nil
    case "rename", "move":
      return try await move(operation, from: source, to: target)
    case "delete":
      return await run(["delete", "path=\(operation.path)"]) { !FileManager.default.fileExists(atPath: source.path) }
    case "set_property":
      return try await setProperty(operation, content: content)
    default:
      return .failed(code: Code.unsupported)
    }
  }

  /// An operation that a pass before this one applied, and whose result
  /// did not reach notes: an `update` or a `create` whose file has the hash of
  /// the content, a `rename` or a `move` whose source is gone and whose target
  /// has the base hash, or a `delete` whose file is gone.
  func alreadyApplied(_ operation: DeviceOperation, local: String?, target: URL) throws -> DeviceOperationOutcome? {
    switch (operation.kind, local) {
    case ("update", .some), ("create", .some):
      return local == operation.contentSHA256 ? .applied(sha256: local) : nil
    case ("delete", nil):
      return operation.baseHash == nil ? nil : .applied(sha256: nil)
    case ("rename", nil), ("move", nil):
      let moved = try files.sha256(at: target)
      // Obsidian can rewrite a link inside the renamed file: the expected hash.
      let known = [operation.expectedSHA256, operation.baseHash].compactMap { $0 }
      return operation.baseHash != nil && moved.map(known.contains) == true ? .applied(sha256: moved) : nil
    default:
      return nil
    }
  }

  /// A rename that keeps the folder and the extension is `obsidian rename`;
  /// every other rename and move is `obsidian move`. Both update the links.
  private func move(_ operation: DeviceOperation, from source: URL, to target: URL) async throws -> DeviceOperationOutcome? {
    guard !FileManager.default.fileExists(atPath: target.path) else {
      return .failed(code: Code.targetExists)
    }
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    let sameFolder = source.deletingLastPathComponent() == target.deletingLastPathComponent()
    let arguments =
      operation.kind == "rename" && sameFolder && source.pathExtension == target.pathExtension
      ? ["rename", "path=\(operation.path)", "name=\(target.deletingPathExtension().lastPathComponent)"]
      : ["move", "path=\(operation.path)", "to=\(operation.resultPath)"]
    return await run(arguments) {
      FileManager.default.fileExists(atPath: target.path) && !FileManager.default.fileExists(atPath: source.path)
    }
  }

  /// The bytes of the operation, when their hash is the hash of its content.
  /// Content longer than its `length_bytes` is refused before the hash.
  func verified(_ data: Data, _ operation: DeviceOperation) throws -> Data {
    guard data.count <= operation.contentLength ?? Int.max else {
      throw NotesChannelError.invalidAnswer
    }
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard digest == operation.contentSHA256 else {
      throw NotesChannelError.invalidAnswer
    }
    return data
  }
}
