import AgentCore

func appFixtureRouting() -> ArchiveRouting {
  ArchiveRouting(
    provider: .chatgpt,
    classification: ArchiveClassification(
      container: .zip, provider: .chatgpt, confidence: .strong,
      matchedMarkers: ["chatgpt"]
    ),
    archivePolicy: .archiveAfterUpload
  )
}
