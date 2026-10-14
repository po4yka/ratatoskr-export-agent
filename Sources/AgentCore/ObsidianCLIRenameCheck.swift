import Foundation

/// What one run of the Obsidian CLI printed and how it ended.
public struct ObsidianCLIAnswer: Equatable, Sendable {
  public var status: Int32
  public var output: String

  public init(status: Int32, output: String) {
    self.status = status
    self.output = output
  }
}

/// Runs the Obsidian CLI. Tests inject a fake; the agent never needs the real
/// CLI to report changes.
public protocol ObsidianCLIRunning: Sendable {
  /// Nil when the executable is missing, does not start, or does not end in
  /// time.
  func run(_ arguments: [String]) -> ObsidianCLIAnswer?
}

/// The Obsidian CLI rename check of design D6.
///
/// The official CLI (installer 1.12.7 or later) answers only while the app
/// runs. The check lists the files that Obsidian knows with
/// `obsidian vault=<name> files`. When the list holds the new path and not
/// the old path, the rename is confirmed. When it holds both, Obsidian still
/// has the old file and the pair is refuted. Any other answer is
/// `unavailable`, and the hash pairing decides. One run answers every pair of
/// a scan batch. After an unavailable answer the check does not ask again for
/// `quietPeriod`, so a closed app does not slow a folder rename.
public final class ObsidianCLIRenameCheck: VaultRenameChecking, @unchecked Sendable {
  public static let defaultQuietPeriod: TimeInterval = 60

  private let vaultName: String
  private let runner: any ObsidianCLIRunning
  private let quietPeriod: TimeInterval
  private let now: @Sendable () -> Date
  private let lock = NSLock()
  private var silentUntil: Date?

  public init(
    vaultName: String,
    runner: any ObsidianCLIRunning,
    quietPeriod: TimeInterval = ObsidianCLIRenameCheck.defaultQuietPeriod,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.vaultName = vaultName
    self.runner = runner
    self.quietPeriod = quietPeriod
    self.now = now
  }

  /// Runs the CLI once for a scan batch, or not at all inside the quiet
  /// period. The answer reads the listed files for each pair of the batch.
  public func answer() -> VaultRenameAnswer {
    lock.lock()
    defer {
      lock.unlock()
    }
    if let silentUntil, now() < silentUntil {
      return .unavailable
    }
    guard let known = Self.knownPaths(in: runner.run(["vault=\(vaultName)", "files"])) else {
      silentUntil = now().addingTimeInterval(quietPeriod)
      return .unavailable
    }
    silentUntil = nil
    return VaultRenameAnswer { [self] oldPath, newPath in
      let verdict = Self.verdict(renaming: oldPath, to: newPath, known: known)
      if verdict == .unavailable {
        lock.withLock { silentUntil = now().addingTimeInterval(quietPeriod) }
      }
      return verdict
    }
  }

  /// Asks once for one pair.
  public func verdict(renaming oldPath: String, to newPath: String) -> VaultRenameVerdict {
    answer().verdict(renaming: oldPath, to: newPath)
  }

  private static func knownPaths(in answer: ObsidianCLIAnswer?) -> Set<String>? {
    guard let answer, answer.status == 0 else {
      return nil
    }
    return Set(
      answer.output.split(whereSeparator: \.isNewline).map {
        VaultPaths.nfc($0.trimmingCharacters(in: .whitespaces))
      }
    )
  }

  private static func verdict(renaming oldPath: String, to newPath: String, known: Set<String>) -> VaultRenameVerdict {
    guard known.contains(VaultPaths.nfc(newPath)) else {
      return .unavailable
    }
    return known.contains(VaultPaths.nfc(oldPath)) ? .refuted : .confirmed
  }
}
