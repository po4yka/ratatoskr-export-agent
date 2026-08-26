import Foundation

enum DocumentRejection: Error, CustomStringConvertible {
  case unsupportedSchemaVersion(Int?)
  case unknownField(String)
  case insecureBackendEndpoint(String)
  case nonPositiveValue(field: String, value: Int)

  var description: String {
    switch self {
    case .unsupportedSchemaVersion(.some(let actual)):
      "only schema version 1 is supported, found \(actual)"
    case .unsupportedSchemaVersion(.none):
      "only schema version 1 is supported, none declared"
    case .unknownField(let name):
      "unknown configuration field \"\(name)\""
    case .insecureBackendEndpoint(let endpoint):
      "backend endpoint must use https or plain http on a loopback host, got \(endpoint)"
    case .nonPositiveValue(let field, let value):
      "configuration field \"\(field)\" must be greater than zero, got \(value)"
    }
  }
}
