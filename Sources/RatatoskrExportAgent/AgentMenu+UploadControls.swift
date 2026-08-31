import AgentCore
import AppKit

@MainActor
extension AgentMenu {
  static func addUploadControls(
    status: UploadQueueStatus, coordinator: AgentMenuCoordinator, to menu: NSMenu
  ) {
    guard let item = uploadControls(status: status, coordinator: coordinator) else { return }
    menu.addItem(item)
  }

  static func uploadControls(
    status: UploadQueueStatus, coordinator: AgentMenuCoordinator
  ) -> NSMenuItem? {
    let actionable = status.items.filter { $0.canPause || $0.canRetry || $0.canCancel }
    guard !actionable.isEmpty else { return nil }
    let item = NSMenuItem(title: "Uploads", action: nil, keyEquivalent: "")
    item.tag = uploadControlsItemTag
    let submenu = NSMenu()
    if actionable.count == 1, let upload = actionable.first {
      addUploadActions(upload, coordinator: coordinator, to: submenu)
    } else {
      for upload in actionable {
        let row = NSMenuItem(title: upload.title, action: nil, keyEquivalent: "")
        let rowMenu = NSMenu()
        addUploadActions(upload, coordinator: coordinator, to: rowMenu)
        row.submenu = rowMenu
        submenu.addItem(row)
      }
    }
    item.submenu = submenu
    return item
  }

  private static func addUploadActions(
    _ upload: UploadQueueItemStatus,
    coordinator: AgentMenuCoordinator,
    to menu: NSMenu
  ) {
    if upload.canPause {
      menu.addItem(uploadAction(
        title: "Pause", action: #selector(AgentMenuCoordinator.pauseUploadSelected(_:)),
        uploadID: upload.id, coordinator: coordinator
      ))
    }
    if upload.canRetry {
      menu.addItem(uploadAction(
        title: "Retry Now", action: #selector(AgentMenuCoordinator.retryUploadSelected(_:)),
        uploadID: upload.id, coordinator: coordinator
      ))
    }
    if upload.canCancel {
      menu.addItem(uploadAction(
        title: "Cancel", action: #selector(AgentMenuCoordinator.cancelUploadSelected(_:)),
        uploadID: upload.id, coordinator: coordinator
      ))
    }
  }

  private static func uploadAction(
    title: String, action: Selector, uploadID: UUID, coordinator: AgentMenuCoordinator
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = coordinator
    item.representedObject = uploadID
    return item
  }
}
