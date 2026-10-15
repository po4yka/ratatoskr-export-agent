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
    static let unsafePath = "notes.write.unsafe_path"
    static let targetExists = "export_agent.write.target_exists"
    static let cliFailed = "export_agent.write.obsidian_failed"
    static let unsupported = "export_agent.write.unsupported_operation"
    /// A local error: the code that the plugin gives for the same case.
    static let refused = "notes.channel.refused"
  }

  let files: VaultFileAccess
  let vaultName: String
  let runner: any ObsidianCLIRunning
  let obsidianRunning: @Sendable () -> Bool
  let settle: @Sendable () async -> Void

  public init(
    vault: URL, vaultName: String, runner: any ObsidianCLIRunning, obsidianRunning: @escaping @Sendable () -> Bool,
    settle: @escaping @Sendable () async -> Void = { try? await Task.sleep(nanoseconds: 500_000_000) }
  ) {
    files = VaultFileAccess(root: vault)
    self.vaultName = vaultName
    self.runner = runner
    self.obsidianRunning = obsidianRunning
    self.settle = settle
  }

  /// The name of the thread of each CLI run.
  static let threadName = "obsidian-cli"

  /// Whether the app runs and its CLI answers `obsidian version`.
  func isAvailable() async -> Bool {
    guard obsidianRunning(), let answer = await cli(["version"]) else {
      return false
    }
    return answer.status == 0
  }

  /// Runs the CLI on a thread of its own, so a run of up to 30 seconds
  /// holds no thread of the cooperative pool.
  private func cli(_ arguments: [String]) async -> ObsidianCLIAnswer? {
    await withCheckedContinuation { [runner] continuation in
      let thread = Thread { continuation.resume(returning: runner.run(arguments)) }
      thread.name = Self.threadName
      thread.start()
    }
  }

  /// Applies one operation. `content` reads its bytes from notes. An error
  /// of that read (the transport) ends the pass and leaves the operation in
  /// the queue; any other error settles it as `failed` with
  /// `notes.channel.refused`, so the pass goes on.
  func apply(
    _ operation: DeviceOperation, content: @escaping @Sendable () async throws -> Data
  ) async throws -> DeviceOperationOutcome {
    let reading: @Sendable () async throws -> Data = {
      do {
        return try await content()
      } catch {
        throw ContentReadError(underlying: error)
      }
    }
    do {
      return try await applyChecked(operation, content: reading)
    } catch let failure as ContentReadError {
      throw failure.underlying
    } catch {
      return .failed(code: Code.refused)
    }
  }

  private func applyChecked(
    _ operation: DeviceOperation, content: @Sendable () async throws -> Data
  ) async throws -> DeviceOperationOutcome {
    guard let source = files.url(of: operation.path), let target = files.url(of: operation.resultPath),
          let notes = linkingNotes(of: operation) else {
      return .failed(code: Code.unsafePath)
    }
    let local = try files.sha256(at: source)
    if let done = try alreadyApplied(operation, local: local, target: target) {
      return try await reportingRewrites(done, notes)
    }
    if let done = try await finishedCreate(operation, local: local, source: source, content: content) {
      return done
    }
    guard local == operation.baseHash else {
      return .baseMismatch(localSHA256: local)
    }
    if let refused = try rewriteMismatch(notes, local: local) {
      return refused
    }
    if let refused = try await change(operation, source: source, target: target, content: content) {
      return refused
    }
    return try await reportingRewrites(.applied(sha256: try await resultHash(operation, at: target)), notes)
  }

  /// Runs one CLI command on the vault. Nil when the command ran and the disk
  /// shows its effect; `awaitingObsidian` when the CLI gave no answer.
  func run(_ command: [String], expecting effect: () -> Bool = { true }) async -> DeviceOperationOutcome? {
    guard let answer = await cli(["vault=\(vaultName)"] + command) else {
      return .awaitingObsidian
    }
    guard answer.status == 0, !answer.output.hasPrefix("Error"), effect() else {
      return .failed(code: Code.cliFailed)
    }
    return nil
  }
}

/// An error of the content read, which the apply step gives back as it is.
private struct ContentReadError: Error {
  let underlying: any Error
}
