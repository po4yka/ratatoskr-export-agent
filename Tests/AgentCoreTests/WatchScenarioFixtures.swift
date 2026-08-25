import AgentCore
import Foundation
import XCTest

/// Scripted filesystem facts driving watcher scenarios without kernel
/// event timing: per-path facts default to benign eligible values.
final class ScriptedFolderMetadata: FileMetadataProviding, @unchecked Sendable {
  private let lock = NSLock()
  private var snapshots: [String: FileSnapshot] = [:]
  private var regularPaths: Set<String> = []
  private var unreadablePaths: Set<String> = []
  private var heldPaths: Set<String> = []
  private var listings: [String: Result<[URL], Error>] = [:]

  func registerCandidate(_ url: URL, byteSize: Int, modifiedAt: Date) {
    let folderPath = url.deletingLastPathComponent().path
    lock.lock()
    defer {
      lock.unlock()
    }
    snapshots[url.path] = FileSnapshot(byteSize: byteSize, modifiedAt: modifiedAt)
    regularPaths.insert(url.path)
    var known: [URL] = []
    if case .success(let existing)? = listings[folderPath] {
      known = existing
    }
    listings[folderPath] = .success(known + [url])
  }

  func failListings(of directory: URL, with error: Error) {
    lock.lock()
    defer {
      lock.unlock()
    }
    listings[directory.path] = .failure(error)
  }

  func markHeld(_ path: String) {
    lock.lock()
    defer {
      lock.unlock()
    }
    heldPaths.insert(path)
  }

  func snapshot(ofItemAtPath path: String) -> FileSnapshot? {
    lock.lock()
    defer {
      lock.unlock()
    }
    return snapshots[path]
  }

  func isRegularFile(atPath path: String) -> Bool {
    lock.lock()
    defer {
      lock.unlock()
    }
    return regularPaths.contains(path)
  }

  func isReadableFile(atPath path: String) -> Bool {
    lock.lock()
    defer {
      lock.unlock()
    }
    return !unreadablePaths.contains(path)
  }

  func writerHoldDetected(atPath path: String) -> Bool {
    lock.lock()
    defer {
      lock.unlock()
    }
    return heldPaths.contains(path)
  }

  func contentsOfDirectory(at url: URL) throws -> [URL] {
    lock.lock()
    defer {
      lock.unlock()
    }
    switch listings[url.path] ?? .success([]) {
    case .failure(let error):
      throw error
    case .success(let urls):
      return urls
    }
  }
}

/// Scripted folder monitor whose activity the test fires by hand.
final class ScriptedInboxMonitor: InboxFolderMonitoring, @unchecked Sendable {
  private let lock = NSLock()
  private var handler: (@Sendable () -> Void)?
  private var startedCount = 0
  private var stoppedCount = 0
  let startFailure: Error?

  init(startFailure: Error? = nil) {
    self.startFailure = startFailure
  }

  func start(onActivity: @escaping @Sendable () -> Void) throws {
    lock.lock()
    defer {
      lock.unlock()
    }
    startedCount += 1
    if let startFailure {
      throw startFailure
    }
    handler = onActivity
  }

  func stop() {
    lock.lock()
    defer {
      lock.unlock()
    }
    stoppedCount += 1
    handler = nil
  }

  func simulateActivity() {
    lock.lock()
    let currentHandler = handler
    lock.unlock()
    currentHandler?()
  }

  func isStarted() -> Bool {
    lock.lock()
    defer {
      lock.unlock()
    }
    return startedCount > 0 && stoppedCount == 0
  }
}
