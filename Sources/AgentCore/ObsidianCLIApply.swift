import Foundation

/// The apply step of the `cli` channel (workspace spec `notes-write-delivery`).
public struct ObsidianCLIApply: Sendable {
  let vault: URL
  let vaultName: String
  let runner: any ObsidianCLIRunning
  let obsidianRunning: @Sendable () -> Bool

  public init(vault: URL, vaultName: String, runner: any ObsidianCLIRunning, obsidianRunning: @escaping @Sendable () -> Bool) {
    self.vault = vault
    self.vaultName = vaultName
    self.runner = runner
    self.obsidianRunning = obsidianRunning
  }

  func apply(_ operation: DeviceOperation, content: @Sendable () async throws -> Data) async throws -> DeviceOperationOutcome {
    .awaitingObsidian
  }
}
