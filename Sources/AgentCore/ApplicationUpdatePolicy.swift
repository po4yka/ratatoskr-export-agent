import Foundation

public enum ApplicationUpdatePolicy {
  public static let releasesURL = URL(
    string: "https://github.com/po4yka/ratatoskr-export-agent/releases/latest"
  )!

  public static func currentVersion(in bundle: Bundle = .main) -> String? {
    guard let value = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
          !value.isEmpty
    else { return nil }
    return value
  }

  public static func diagnostics(currentVersion: String?) -> UpdateCheckDiagnostics {
    let version = currentVersion.flatMap { $0.isEmpty ? nil : $0 }
    return .manualDownload(currentVersion: version)
  }
}
