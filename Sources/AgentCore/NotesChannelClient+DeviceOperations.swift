import Foundation

extension NotesChannelClient {
  /// Reads the queue of the connection and applies its operations in order.
  public func applyQueuedOperations(
    _ apply: ObsidianCLIApply, onLocalChange: @escaping @Sendable ([VaultChange]) -> Void = { _ in }
  ) async throws -> DeviceQueuePass {
    .answered(0)
  }
}
