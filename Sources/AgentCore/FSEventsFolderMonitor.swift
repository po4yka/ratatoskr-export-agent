import CoreServices
import Foundation

/// Why a platform-level folder monitor refused to start.
public enum FolderMonitorFailure: Error, Equatable {
  /// Nothing (or nothing directory-shaped) exists at the folder location.
  case folderUnavailable
}

/// Boxes the activity handler so it can cross into the C callback.
private final class ActivityHandlerBox: @unchecked Sendable {
  let work: @Sendable () -> Void

  init(work: @escaping @Sendable () -> Void) {
    self.work = work
  }
}

/// C-callable bridge from FSEvents to the boxed handler. The event paths
/// are deliberately ignored: notifications are hints, scans re-list.
private let fsEventsCallback: FSEventStreamCallback = { _, clientInfo, _, _, _, _ in
  guard let clientInfo else {
    return
  }
  let box = Unmanaged<ActivityHandlerBox>.fromOpaque(clientInfo).takeUnretainedValue()
  box.work()
}

/// FSEvents-backed observation of one folder's activity, chosen over
/// DispatchSource vnode sources because it discovers newly created files,
/// survives rename/delete churn, and coalesces bursts natively. The
/// monitor reports only that activity happened inside the folder;
/// consumers treat notifications as hints and re-list the directory.
public final class FSEventsFolderMonitor: InboxFolderMonitoring, @unchecked Sendable {
  private let url: URL
  private let lock = NSLock()
  private var stream: FSEventStreamRef?
  private var handlerBox: ActivityHandlerBox?
  private lazy var deliveryQueue = DispatchQueue(label: "ratatoskr.export-agent.fsevents")

  public init(url: URL) {
    self.url = url
  }

  /// Whether a live stream currently exists for this monitor.
  public var isObserving: Bool {
    lock.lock()
    defer {
      lock.unlock()
    }
    return stream != nil
  }

  /// Validates the folder and starts a file-level event stream. Refuses
  /// closed instead of leaving a dead stream behind.
  public func start(onActivity: @escaping @Sendable () -> Void) throws {
    lock.lock()
    defer {
      lock.unlock()
    }
    guard stream == nil else {
      return
    }
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    guard exists, isDirectory.boolValue else {
      throw FolderMonitorFailure.folderUnavailable
    }
    let box = ActivityHandlerBox(work: onActivity)
    let created = try makeStream(deliveringTo: box)
    FSEventStreamSetDispatchQueue(created, deliveryQueue)
    guard FSEventStreamStart(created) else {
      FSEventStreamInvalidate(created)
      FSEventStreamRelease(created)
      throw FolderMonitorFailure.folderUnavailable
    }
    handlerBox = box
    stream = created
  }

  /// Creates the raw FSEventStream for this folder at file-level detail.
  private func makeStream(
    deliveringTo box: ActivityHandlerBox
  ) throws -> FSEventStreamRef {
    var context = FSEventStreamContext(
      version: 0,
      info: Unmanaged.passUnretained(box).toOpaque(),
      retain: nil,
      release: nil,
      copyDescription: nil
    )
    let watchedPaths = [url.path] as CFArray
    let latencySeconds = 0.3
    let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
    guard
      let created = FSEventStreamCreate(
        kCFAllocatorDefault,
        fsEventsCallback,
        &context,
        watchedPaths,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        latencySeconds,
        flags
      )
    else {
      throw FolderMonitorFailure.folderUnavailable
    }
    return created
  }

  /// Stops and releases the stream; safe to call repeatedly.
  public func stop() {
    lock.lock()
    defer {
      lock.unlock()
    }
    guard let current = stream else {
      return
    }
    FSEventStreamStop(current)
    FSEventStreamInvalidate(current)
    FSEventStreamRelease(current)
    stream = nil
    handlerBox = nil
  }
}
