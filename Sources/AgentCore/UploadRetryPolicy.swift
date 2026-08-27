import Foundation

/// Deterministic bounded retry timing for retryable transfer failures.
public struct UploadRetryPolicy: Sendable {
  public let initialDelay: TimeInterval
  public let maximumDelay: TimeInterval

  public init(initialDelay: TimeInterval = 5, maximumDelay: TimeInterval = 3600) {
    self.initialDelay = initialDelay
    self.maximumDelay = maximumDelay
  }

  public func nextEligible(at now: Date, attempt: Int, retryAfter: TimeInterval? = nil) -> Date {
    let exponent = max(0, attempt - 1)
    let backoff = min(maximumDelay, initialDelay * pow(2, Double(exponent)))
    return now.addingTimeInterval(max(backoff, retryAfter ?? 0))
  }
}

/// One shared non-blocking reservation point for all queued transfers.
public actor UploadAdmissionLimiter {
  private let maximumActive: Int
  private let bytesPerTick: Int
  private var active = 0
  private var admittedBytes = 0

  public init(maximumActive: Int, bytesPerTick: Int) {
    self.maximumActive = maximumActive
    self.bytesPerTick = bytesPerTick
  }

  public func beginTick() {
    admittedBytes = 0
  }

  public func acquireUploadSlot() -> Bool {
    guard active < maximumActive else { return false }
    active += 1
    return true
  }

  /// Admits bytes before the uploader reads a chunk into memory.
  public func reserveBytes(bytes: Int) -> Bool {
    guard bytes > 0, bytes <= bytesPerTick - admittedBytes else { return false }
    admittedBytes += bytes
    return true
  }

  /// Compatibility-sized atomic reservation used by existing callers.
  public func reserve(bytes: Int) -> Bool {
    guard acquireUploadSlot() else { return false }
    guard reserveBytes(bytes: bytes) else {
      releaseUploadSlot()
      return false
    }
    return true
  }

  public func releaseUploadSlot() {
    active = max(0, active - 1)
  }

  public func release() {
    releaseUploadSlot()
  }

  public var activeUploads: Int {
    active
  }

  public var bytesAdmittedThisTick: Int {
    admittedBytes
  }
}
