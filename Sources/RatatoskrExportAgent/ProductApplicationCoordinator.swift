import AgentCore
import AppKit
import Network

@MainActor
final class ProductApplicationCoordinator: NSObject, NSApplicationDelegate {
  private var graph: ProductRuntimeGraph?
  private var statusBinding: UploadMenuStatusBinding?
  private var timer: Timer?
  private var observers: [NSObjectProtocol] = []
  private let networkMonitor = NWPathMonitor()

  func applicationDidFinishLaunching(_: Notification) {
    Task {
      do {
        let graph = try await ProductRuntimeFactory.make()
        self.graph = graph
        installProductRuntime(graph)
        if let menu = installedAgentMenu() {
          statusBinding = UploadMenuStatusBinding(
            menu: menu, updates: await graph.queue.statusUpdates())
          AgentMenu.apply(importEntries: graph.journal.entries, to: menu)
        }
        installLifecycleTriggers()
        await graph.runtime.start()
        refreshImportStatus()
      } catch {
        presentRuntimeFailure()
      }
    }
  }

  func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
    guard let runtime = graph?.runtime else { return .terminateNow }
    Task {
      await runtime.stop()
      NSApplication.shared.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  private func installLifecycleTriggers() {
    timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { await self?.reconcileAndRefresh() }
    }
    for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
      observers.append(
        NSWorkspace.shared.notificationCenter.addObserver(
          forName: name, object: nil, queue: .main
        ) { [weak self] _ in Task { await self?.reconcileAndRefresh() } })
    }
    networkMonitor.pathUpdateHandler = { [weak self] path in
      guard path.status == .satisfied else { return }
      Task { await self?.reconcileAndRefresh() }
    }
    networkMonitor.start(queue: DispatchQueue(label: "ratatoskr.export-agent.network"))
  }

  private func reconcileAndRefresh() async {
    guard let graph else { return }
    await graph.refreshFolders()
    await graph.runtime.reconcile()
    refreshImportStatus()
  }

  private func refreshImportStatus() {
    guard let graph, let menu = installedAgentMenu() else { return }
    AgentMenu.apply(importEntries: graph.journal.entries, to: menu)
  }

  private func presentRuntimeFailure() {
    let alert = NSAlert()
    alert.messageText = "Ratatoskr Export Agent could not start."
    alert.informativeText = "Open Diagnostics after repairing the local configuration."
    alert.alertStyle = .critical
    alert.runModal()
  }
}
