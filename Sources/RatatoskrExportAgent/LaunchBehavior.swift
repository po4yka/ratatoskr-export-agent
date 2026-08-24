import AppKit

@MainActor
private var installedStatusItem: NSStatusItem?

@MainActor
func applyBootstrapPresentation() {
  NSApplication.shared.setActivationPolicy(.accessory)

  guard installedStatusItem == nil else { return }

  let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  statusItem.button?.title = "Ratatoskr"
  installedStatusItem = statusItem
}

@MainActor
func isBootstrapPresentationInstalled() -> Bool {
  installedStatusItem != nil
}
