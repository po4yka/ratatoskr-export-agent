import AgentCore
import AppKit
import SwiftUI

@MainActor
final class DiagnosticsWindowController: NSWindowController {
  private let viewModel: DiagnosticsViewModel
  private var context: DiagnosticsSnapshotContext
  private var refreshTask: Task<Void, Never>?

  private init(context: DiagnosticsSnapshotContext) {
    self.context = context
    viewModel = DiagnosticsViewModel(snapshot: context.snapshot)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 660, height: 360),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Ratatoskr Diagnostics"
    super.init(window: window)
    window.contentView = NSHostingView(
      rootView: DiagnosticsView(viewModel: viewModel) { [weak self] in
        self?.exportSupportReport()
      }
    )
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("DiagnosticsWindowController is not created from coders")
  }

  static func makeDefault() -> DiagnosticsWindowController {
    let controller = DiagnosticsWindowController(
      context: DiagnosticsSnapshotLoader.loadContext(
        notificationAuthorization: .deniedOrUnavailable
      )
    )
    controller.refreshNotificationAuthorization()
    return controller
  }

  func showDiagnostics() {
    NSApplication.shared.activate()
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
  }

  private func refreshNotificationAuthorization() {
    refreshTask = Task { [weak self] in
      let authorization = await UserAgentNotificationService().authorization()
      guard !Task.isCancelled else { return }
      let context = DiagnosticsSnapshotLoader.loadContext(
        notificationAuthorization: authorization
      )
      self?.context = context
      self?.viewModel.replace(with: context.snapshot)
    }
  }

  private func exportSupportReport() {
    do {
      let items = try context.entries.map(SupportReportItemSummary.init(entry:))
      let data = try SupportReportBuilder.make(
        snapshot: context.snapshot,
        items: items,
        failures: [],
        generatedAt: Date(),
        buildInfo: Self.buildInfo
      )
      guard presentPreview(for: data) else { return }
      let panel = NSSavePanel()
      panel.nameFieldStringValue = "ratatoskr-support-report.json"
      panel.canCreateDirectories = true
      guard panel.runModal() == .OK, let destination = panel.url else { return }
      try SupportReportExporter().export(previewData: data, to: destination)
    } catch {
      presentExportFailure()
    }
  }

  private func presentPreview(for data: Data) -> Bool {
    guard let report = String(data: data, encoding: .utf8) else { return false }
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 620, height: 320))
    textView.string = report
    textView.isEditable = false
    textView.isSelectable = true
    textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    let scrollView = NSScrollView(frame: textView.frame)
    scrollView.documentView = textView
    scrollView.hasVerticalScroller = true
    scrollView.borderType = .bezelBorder

    let alert = NSAlert()
    alert.messageText = "Review redacted support report"
    alert.informativeText = "Only the exact JSON shown below will be saved locally."
    alert.accessoryView = scrollView
    alert.addButton(withTitle: "Choose Save Location…")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }

  private func presentExportFailure() {
    let alert = NSAlert()
    alert.messageText = "Support report could not be exported."
    alert.informativeText = "No report was uploaded or transmitted. Try again after checking Diagnostics."
    alert.alertStyle = .warning
    alert.runModal()
  }

  private static var buildInfo: SupportReportBuildInfo {
    let info = Bundle.main.infoDictionary
    return SupportReportBuildInfo(
      version: safeBuildValue(info?["CFBundleShortVersionString"] as? String),
      build: safeBuildValue(info?["CFBundleVersion"] as? String)
    )
  }

  private static func safeBuildValue(_ value: String?) -> String {
    guard let value,
          !value.isEmpty,
          value.count <= 64,
          value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) })
    else { return "development" }
    return value
  }

  deinit {
    refreshTask?.cancel()
  }
}
