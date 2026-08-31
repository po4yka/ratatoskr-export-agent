import AgentCore
import AppKit

/// Handles status-bar menu selections.
@MainActor
final class AgentMenuCoordinator: NSObject {
  private var settingsWindowController: SettingsWindowController?
  private var diagnosticsWindowController: DiagnosticsWindowController?
  private var graph: ProductRuntimeGraph?
  private let openUpdateURL: (URL) -> Bool
  private let presentUpdateFailure: () -> Void

  override convenience init() {
    self.init(
      openUpdateURL: { NSWorkspace.shared.open($0) },
      presentUpdateFailure: Self.presentUpdateOpenFailure
    )
  }

  init(
    openUpdateURL: @escaping (URL) -> Bool,
    presentUpdateFailure: @escaping () -> Void
  ) {
    self.openUpdateURL = openUpdateURL
    self.presentUpdateFailure = presentUpdateFailure
    super.init()
  }

  @objc
  func diagnosticsSelected() {
    if diagnosticsWindowController == nil {
      diagnosticsWindowController = DiagnosticsWindowController.makeDefault()
    }
    diagnosticsWindowController?.showDiagnostics()
  }

  @objc
  func settingsSelected() {
    if settingsWindowController == nil {
      guard let graph else {
        presentLoadFailure()
        return
      }
      settingsWindowController = SettingsWindowController(
        registry: graph.registry,
        session: graph.session,
        onFoldersChanged: { [weak self] in self?.refreshFolders() }
      )
    }
    settingsWindowController?.showSettings()
  }

  func install(graph: ProductRuntimeGraph) { self.graph = graph }

  @objc
  func pauseUploadSelected(_ sender: NSMenuItem) {
    performUploadControl(sender) { queue, id in try await queue.pause(entryID: id) }
  }

  @objc
  func retryUploadSelected(_ sender: NSMenuItem) {
    performUploadControl(sender) { queue, id in try await queue.retryNow(entryID: id) }
  }

  @objc
  func cancelUploadSelected(_ sender: NSMenuItem) {
    performUploadControl(sender) { queue, id in try await queue.cancel(entryID: id) }
  }

  private func performUploadControl(
    _ sender: NSMenuItem,
    operation: @escaping @Sendable (UploadQueue, UUID) async throws -> Void
  ) {
    guard let queue = graph?.queue, let id = sender.representedObject as? UUID else {
      presentUploadControlFailure()
      return
    }
    Task {
      do {
        try await operation(queue, id)
      } catch {
        presentUploadControlFailure()
      }
    }
  }

  private func refreshFolders() {
    guard let graph else { return }
    Task {
      await graph.refreshFolders()
      await graph.runtime.reconcile()
    }
  }

  @objc
  func checkForUpdatesSelected() {
    guard openUpdateURL(ApplicationUpdatePolicy.releasesURL) else {
      presentUpdateFailure()
      return
    }
  }

  @objc
  func quitSelected() {
    NSApplication.shared.terminate(nil)
  }

  private func presentLoadFailure() {
    let alert = NSAlert()
    alert.messageText = "Watched folder settings could not be loaded."
    alert.informativeText =
      "The stored settings document is invalid. Repair or remove it, then reopen Settings."
    alert.alertStyle = .warning
    alert.runModal()
  }

  private func presentUploadControlFailure() {
    let alert = NSAlert()
    alert.messageText = "The upload could not be updated."
    alert.informativeText = "Refresh the menu and try again."
    alert.alertStyle = .warning
    alert.runModal()
  }

  private static func presentUpdateOpenFailure() {
    let alert = NSAlert()
    alert.messageText = "The Ratatoskr releases page could not be opened."
    alert.informativeText =
      "Try again, or open the Ratatoskr Export Agent releases page in your browser."
    alert.alertStyle = .warning
    alert.runModal()
  }
}
