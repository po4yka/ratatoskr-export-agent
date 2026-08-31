import AgentCore

func fixtureRouting(
  provider: PlatformArchiveProvider = .chatgpt,
  policy: FolderArchivePolicy = .archiveAfterUpload
) -> ArchiveRouting {
  ArchiveRouting(
    provider: provider,
    classification: ArchiveClassification(
      container: .zip,
      provider: provider == .chatgpt ? .chatgpt : .claude,
      confidence: .strong,
      matchedMarkers: [provider.rawValue]
    ),
    archivePolicy: policy
  )
}
