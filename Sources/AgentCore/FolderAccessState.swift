import Foundation

/// The user-facing accessibility of one registered watched folder. Every
/// state is actionable; a broken bookmark never leaves the folder silently
/// unwatched.
public enum FolderAccessState: Equatable, Sendable {
  /// The folder resolved and its contents are readable.
  case accessible(URL)

  /// The bookmark bytes no longer grant access (corrupt, or the folder was
  /// moved or replaced); the user must pick the folder again.
  case needsReauthorization

  /// Access resolves, but nothing exists at the target any more.
  case missing

  /// The system refused reading the folder's contents.
  case denied
}

/// What the filesystem layer observed while evaluating one folder's access.
///
/// Translation from raw bookmark/permission outcomes into observations is
/// the evaluator's job; mapping observations onto user-facing states is this
/// pure classifier's job.
public enum FolderAccessObservation: Equatable, Sendable {
  /// Bookmark bytes could not be parsed or resolved to a location.
  case bookmarkUnresolvable

  /// Resolution succeeded but flagged the stored bookmark as stale while
  /// the target still exists.
  case resolvedStale

  /// Resolution produced a location where nothing exists any more.
  case targetVanished

  /// Reading the folder's existence or contents was refused by permissions.
  case unreadableDueToPermissions

  /// All checks passed; contents are readable at the resolved URL.
  case readable(URL)
}

/// Maps filesystem access observations onto user-facing folder states.
public enum FolderAccessClassifier {
  public static func state(for observation: FolderAccessObservation) -> FolderAccessState {
    switch observation {
    case .bookmarkUnresolvable, .resolvedStale:
      .needsReauthorization
    case .targetVanished:
      .missing
    case .unreadableDueToPermissions:
      .denied
    case .readable(let url):
      .accessible(url)
    }
  }
}
