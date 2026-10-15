import Foundation

extension VaultChannelSync {
  /// The task that reads the queue of the writes every `interval`. A failed
  /// pass, or a pass that waits for Obsidian, is read again after the
  /// interval. A base mismatch gives the local file to the buffer, so the one
  /// send task sends it.
  static func queueReader(
    client: NotesChannelClient, buffer: VaultChangeBuffer, operations: ObsidianCLIApply, interval: TimeInterval
  ) -> Task<Void, Never> {
    Task {
      while !Task.isCancelled {
        _ = try? await client.applyQueuedOperations(operations) { buffer.add($0) }
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
      }
    }
  }
}
