import AgentCore
import Foundation

// Shared layout helpers for archive-store tests. Internal on purpose: one
// definition per name across the AgentCoreTests module.

/// The store segment name for an advisory provider label.
func providerSegmentName(_ provider: ArchiveProviderHint) -> String {
  switch provider {
  case .chatgpt:
    "chatgpt"
  case .claude:
    "claude"
  case .instagram:
    "instagram"
  case .threads:
    "threads"
  case .unidentified:
    "unidentified"
  }
}

/// The month directory the store derives from an archival date.
func storeLayoutMonthDirectory(
  storeRoot: URL,
  provider: ArchiveProviderHint,
  on date: Date
) -> URL {
  let components = Calendar.current.dateComponents([.year, .month], from: date)
  return
    storeRoot
    .appendingPathComponent(providerSegmentName(provider), isDirectory: true)
    .appendingPathComponent(String(components.year ?? 0), isDirectory: true)
    .appendingPathComponent(String(format: "%02d", components.month ?? 0), isDirectory: true)
}
