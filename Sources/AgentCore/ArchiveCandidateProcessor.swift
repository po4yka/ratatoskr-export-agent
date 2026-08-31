import Foundation

public enum ArchiveCandidateProcessingError: Error, Equatable, Sendable {
  case unsupportedProvider(ArchiveProviderHint)
  case missingFolderPolicy
}

public protocol ArchiveClassifying: Sendable {
  func classify(at url: URL) throws -> ArchiveClassification
}

extension ArchiveClassifier: ArchiveClassifying {}

/// Converts stable inbox candidates into immutable, provider-routed durable queue entries.
public actor ArchiveCandidateProcessor {
  private let classifier: any ArchiveClassifying
  private let store: LocalArchiveStore
  private let journal: LocalArchiveJournal
  private var policies: [UUID: FolderArchivePolicy]

  public init(
    classifier: any ArchiveClassifying = ArchiveClassifier(),
    store: LocalArchiveStore,
    journal: LocalArchiveJournal,
    policies: [UUID: FolderArchivePolicy]
  ) {
    self.classifier = classifier
    self.store = store
    self.journal = journal
    self.policies = policies
  }

  @discardableResult
  public func process(_ candidate: StableArchiveCandidate) throws -> JournalEntry {
    guard let policy = policies[candidate.folderID] else {
      throw ArchiveCandidateProcessingError.missingFolderPolicy
    }
    let classification = try classifier.classify(at: candidate.url)
    let provider: PlatformArchiveProvider
    switch classification.provider {
    case .chatgpt: provider = .chatgpt
    case .claude: provider = .claude
    case .instagram, .threads, .unidentified:
      throw ArchiveCandidateProcessingError.unsupportedProvider(classification.provider)
    }
    let preserved = try store.archive(
      sourceAt: candidate.url,
      observedByteSize: candidate.snapshot.byteSize,
      classification: classification
    )
    if let existing = journal.entries.first(where: { $0.fingerprint == preserved.fingerprint }) {
      return existing
    }
    var entry = try journal.discover(
      fingerprint: preserved.fingerprint,
      routing: ArchiveRouting(
        provider: provider, classification: classification, archivePolicy: policy
      ),
      managedArchiveURL: preserved.url
    )
    for state in [JournalState.archived, .hashed, .queued] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }
    return entry
  }

  public func entries() -> [JournalEntry] { journal.entries }

  /// Replaces the live folder-policy projection owned by the shared settings registry.
  public func replacePolicies(_ policies: [UUID: FolderArchivePolicy]) {
    self.policies = policies
  }
}
