import Foundation

/// Runs the installed `obsidian` executable with a time limit.
public struct ProcessObsidianCLIRunner: ObsidianCLIRunning {
  /// Where the Obsidian installer registers the CLI.
  public static let defaultCandidates = [
    "/usr/local/bin/obsidian",
    "/opt/homebrew/bin/obsidian",
  ]

  public let executable: URL?
  public let timeLimit: TimeInterval

  /// Uses the first candidate that is an executable file, or none.
  public init(candidates: [String] = ProcessObsidianCLIRunner.defaultCandidates, timeLimit: TimeInterval = 2) {
    executable = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map {
      URL(fileURLWithPath: $0)
    }
    self.timeLimit = timeLimit
  }

  public func run(_ arguments: [String]) -> ObsidianCLIAnswer? {
    guard let executable else {
      return nil
    }
    let process = Process()
    let output = Pipe()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    let finished = DispatchSemaphore(value: 0)
    let collected = CollectedOutput()
    do {
      try process.run()
    } catch {
      return nil
    }
    // Read while the process runs, so a long list cannot fill the pipe.
    DispatchQueue.global().async {
      collected.data = output.fileHandleForReading.readDataToEndOfFile()
      finished.signal()
    }
    guard finished.wait(timeout: .now() + timeLimit) == .success else {
      process.terminate()
      return nil
    }
    process.waitUntilExit()
    guard let text = String(bytes: collected.data, encoding: .utf8) else {
      return nil
    }
    return ObsidianCLIAnswer(status: process.terminationStatus, output: text)
  }
}

/// Carries the bytes from the reading thread; the semaphore orders access.
private final class CollectedOutput: @unchecked Sendable {
  var data = Data()
}
