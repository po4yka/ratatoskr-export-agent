import CryptoKit
import Foundation

/// The apply step of the `cli` channel (workspace spec `notes-write-delivery`).
///
/// It compares the hash of the local file with the base hash first. It
/// applies `create`, `rename`, `move`, `delete` and `set_property` with the
/// Obsidian CLI (installer 1.12.7 or later), and `update` with an atomic write
/// inside the vault. It never passes `permanent` to `obsidian delete`. The CLI
/// starts the app when the app does not run, so the CLI is asked only while
/// the app runs; otherwise every operation stays in the queue.
public struct ObsidianCLIApply: Sendable {
  /// The bundle id of the Obsidian app.
  public static let bundleIdentifier = "md.obsidian"

  enum Code {
    static let outsideVault = "export_agent.write.path_outside_vault"
    static let targetExists = "export_agent.write.target_exists"
    static let cliFailed = "export_agent.write.obsidian_failed"
    static let unsupported = "export_agent.write.unsupported_operation"
  }

  let files: VaultFileAccess
  let vaultName: String
  let runner: any ObsidianCLIRunning
  let obsidianRunning: @Sendable () -> Bool
  let settle: @Sendable () async -> Void

  public init(
    vault: URL, vaultName: String, runner: any ObsidianCLIRunning, obsidianRunning: @escaping @Sendable () -> Bool,
    settle: @escaping @Sendable () async -> Void = {}
  ) {
    files = VaultFileAccess(root: vault)
    self.vaultName = vaultName
    self.runner = runner
    self.obsidianRunning = obsidianRunning
    self.settle = settle
  }

  /// Whether the app runs and its CLI answers `obsidian version`.
  func isAvailable() -> Bool {
    guard obsidianRunning(), let answer = runner.run(["version"]) else {
      return false
    }
    return answer.status == 0
  }

  /// Applies one operation. `content` reads its bytes from notes.
  func apply(_ operation: DeviceOperation, content: @Sendable () async throws -> Data) async throws -> DeviceOperationOutcome {
    guard let source = files.url(of: operation.path), let target = files.url(of: operation.resultPath) else {
      return .failed(code: Code.outsideVault)
    }
    let local = try files.sha256(at: source)
    if let done = try alreadyApplied(operation, local: local, target: target) {
      return done
    }
    guard local == operation.baseHash else {
      return .baseMismatch(localSHA256: local)
    }
    if let refused = try await change(operation, source: source, target: target, content: content) {
      return refused
    }
    return .applied(sha256: try files.sha256(at: target))
  }

  /// Makes the change of the operation. Nil when the vault has it.
  private func change(
    _ operation: DeviceOperation, source: URL, target: URL, content: @Sendable () async throws -> Data
  ) async throws -> DeviceOperationOutcome? {
    switch operation.kind {
    case "update":
      try files.write(try await verified(content(), operation), to: source)
      return nil
    case "create":
      let bytes = try await verified(content(), operation)
      if let refused = run(["create", "path=\(operation.path)"], expecting: { FileManager.default.fileExists(atPath: source.path) }) {
        return refused
      }
      try files.write(bytes, to: source)
      return nil
    case "rename", "move":
      return move(operation, from: source, to: target)
    case "delete":
      return run(["delete", "path=\(operation.path)"]) { !FileManager.default.fileExists(atPath: source.path) }
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
  private func alreadyApplied(_ operation: DeviceOperation, local: String?, target: URL) throws -> DeviceOperationOutcome? {
    switch (operation.kind, local) {
    case ("update", .some), ("create", .some):
      return local == operation.contentSHA256 ? .applied(sha256: local) : nil
    case ("delete", nil):
      return operation.baseHash == nil ? nil : .applied(sha256: nil)
    case ("rename", nil), ("move", nil):
      let moved = try files.sha256(at: target)
      return operation.baseHash != nil && moved == operation.baseHash ? .applied(sha256: moved) : nil
    default:
      return nil
    }
  }

  /// A rename that keeps the folder and the extension is `obsidian rename`;
  /// every other rename and move is `obsidian move`. Both update the links.
  private func move(_ operation: DeviceOperation, from source: URL, to target: URL) -> DeviceOperationOutcome? {
    guard !FileManager.default.fileExists(atPath: target.path) else {
      return .failed(code: Code.targetExists)
    }
    let sameFolder = source.deletingLastPathComponent() == target.deletingLastPathComponent()
    let arguments =
      operation.kind == "rename" && sameFolder && source.pathExtension == target.pathExtension
      ? ["rename", "path=\(operation.path)", "name=\(target.deletingPathExtension().lastPathComponent)"]
      : ["move", "path=\(operation.path)", "to=\(operation.resultPath)"]
    return run(arguments) {
      FileManager.default.fileExists(atPath: target.path) && !FileManager.default.fileExists(atPath: source.path)
    }
  }

  /// Runs one CLI command on the vault. Nil when the command ran and the disk
  /// shows its effect; `awaitingObsidian` when the CLI gave no answer.
  func run(_ command: [String], expecting effect: () -> Bool = { true }) -> DeviceOperationOutcome? {
    guard let answer = runner.run(["vault=\(vaultName)"] + command) else {
      return .awaitingObsidian
    }
    guard answer.status == 0, !answer.output.hasPrefix("Error"), effect() else {
      return .failed(code: Code.cliFailed)
    }
    return nil
  }

  /// The bytes of the operation, when their hash is the hash of its content.
  private func verified(_ data: Data, _ operation: DeviceOperation) throws -> Data {
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard digest == operation.contentSHA256 else {
      throw NotesChannelError.invalidAnswer
    }
    return data
  }
}
