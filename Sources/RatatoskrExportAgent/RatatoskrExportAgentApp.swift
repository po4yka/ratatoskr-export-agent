import AppKit

@MainActor
@main
struct RatatoskrExportAgentApp {
  private static var activeSmokeCoordinator: SmokeLaunchCoordinator?
  private static var activeProductCoordinator: ProductApplicationCoordinator?

  static func main() {
    let arguments = Array(CommandLine.arguments.dropFirst())

    guard arguments.isEmpty || arguments == ["--smoke"] else {
      FileHandle.standardError.write(Data("usage: RatatoskrExportAgent [--smoke]\n".utf8))
      exit(2)
    }

    let app = NSApplication.shared

    if arguments.contains("--smoke") {
      let coordinator = SmokeLaunchCoordinator()
      activeSmokeCoordinator = coordinator
      app.delegate = coordinator
    } else {
      let coordinator = ProductApplicationCoordinator()
      activeProductCoordinator = coordinator
      app.delegate = coordinator
    }

    applyBootstrapPresentation()

    app.run()
  }
}

@MainActor
final class SmokeLaunchCoordinator: NSObject, NSApplicationDelegate {
  private var watchdogTimer: Timer?

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard isBootstrapPresentationInstalled() else {
      FileHandle.standardError.write(
        Data("smoke launch: status bar presentation is not installed\n".utf8)
      )
      exit(1)
    }

    watchdogTimer = Timer.scheduledTimer(
      timeInterval: 1,
      target: self,
      selector: #selector(smokeWatchdogFired),
      userInfo: nil,
      repeats: false
    )
  }

  @objc private func smokeWatchdogFired() {
    NSApplication.shared.terminate(nil)
  }
}
