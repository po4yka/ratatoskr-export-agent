import CoreServices
import Foundation

/// Names the paths under a vault root that changed. Tests inject a fake.
public protocol VaultEventSource: AnyObject, Sendable {
  /// Starts delivery. `rescan` is true when the platform lost events and the
  /// whole vault must be compared again.
  func start(onEvents: @escaping @Sendable (_ paths: [String], _ rescan: Bool) -> Void) throws

  /// Ends delivery; safe to call repeatedly.
  func stop()
}

private final class VaultEventHandlerBox: @unchecked Sendable {
  let work: @Sendable ([String], Bool) -> Void

  init(work: @escaping @Sendable ([String], Bool) -> Void) {
    self.work = work
  }
}

private let lostEventFlags = FSEventStreamEventFlags(
  kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
    | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged
)

private let vaultEventsCallback: FSEventStreamCallback = { _, clientInfo, count, eventPaths, eventFlags, _ in
  guard let clientInfo else {
    return
  }
  let box = Unmanaged<VaultEventHandlerBox>.fromOpaque(clientInfo).takeUnretainedValue()
  let paths = (Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String]) ?? []
  let flags = UnsafeBufferPointer(start: eventFlags, count: count)
  box.work(paths, flags.contains { $0 & lostEventFlags != 0 })
}

/// FSEvents with file-level events and the changed paths, for one vault root.
public final class FSEventsVaultEventSource: VaultEventSource, @unchecked Sendable {
  private let root: URL
  private let latency: TimeInterval
  private let lock = NSLock()
  private var stream: FSEventStreamRef?
  private var handlerBox: VaultEventHandlerBox?
  private let deliveryQueue = DispatchQueue(label: "ratatoskr.export-agent.vault-fsevents")

  public init(root: URL, latency: TimeInterval = 0.3) {
    self.root = root
    self.latency = latency
  }

  public func start(onEvents: @escaping @Sendable ([String], Bool) -> Void) throws {
    lock.lock()
    defer {
      lock.unlock()
    }
    guard stream == nil else {
      return
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw FolderMonitorFailure.folderUnavailable
    }
    let box = VaultEventHandlerBox(work: onEvents)
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

  private func makeStream(deliveringTo box: VaultEventHandlerBox) throws -> FSEventStreamRef {
    var context = FSEventStreamContext(
      version: 0,
      info: Unmanaged.passUnretained(box).toOpaque(),
      retain: nil,
      release: nil,
      copyDescription: nil
    )
    let flags = UInt32(
      kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes
    )
    guard
      let created = FSEventStreamCreate(
        kCFAllocatorDefault, vaultEventsCallback, &context, [root.path] as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
      )
    else {
      throw FolderMonitorFailure.folderUnavailable
    }
    return created
  }

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
