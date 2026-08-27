import XCTest

func XCTAssertThrowsErrorAsync<T>(_ operation: @escaping @Sendable () async throws -> T) async {
  do {
    _ = try await operation()
    XCTFail("the operation must fail")
  } catch {}
}

func capturedError(_ operation: @escaping @Sendable () async throws -> String) async -> Error? {
  do {
    _ = try await operation()
    return nil
  } catch {
    return error
  }
}
