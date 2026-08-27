import AgentCore
import AppKit

/// Binds menu rendering to queue-owned state without giving AppKit authority
/// to mutate uploads, files, or transport state.
@MainActor
final class UploadMenuStatusBinding {
  private var updateTask: Task<Void, Never>?

  init(menu: NSMenu, updates: AsyncStream<UploadQueueStatus>) {
    updateTask = Task { [weak menu] in
      for await status in updates {
        guard let menu else { return }
        AgentMenu.apply(uploadStatus: status, to: menu)
      }
    }
  }

  deinit {
    updateTask?.cancel()
  }
}
