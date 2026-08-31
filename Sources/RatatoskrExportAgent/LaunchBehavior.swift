import AgentCore
import AppKit

@MainActor
private var installedStatusItem: NSStatusItem?

@MainActor
private var installedMenuCoordinator: AgentMenuCoordinator?

@MainActor
func applyBootstrapPresentation() {
  NSApplication.shared.setActivationPolicy(.accessory)

  guard installedStatusItem == nil else { return }

  let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  statusItem.button?.title = "Ratatoskr"
  let coordinator = AgentMenuCoordinator()
  statusItem.menu = AgentMenu.make(coordinator: coordinator)
  installedMenuCoordinator = coordinator
  installedStatusItem = statusItem
}

@MainActor
func isBootstrapPresentationInstalled() -> Bool {
  installedStatusItem != nil
}

@MainActor
func installedAgentMenu() -> NSMenu? { installedStatusItem?.menu }

@MainActor
func installProductRuntime(_ graph: ProductRuntimeGraph) {
  installedMenuCoordinator?.install(graph: graph)
}
