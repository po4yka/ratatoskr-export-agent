// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ratatoskr-export-agent",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "AgentCore", targets: ["AgentCore"]),
    .library(name: "AgentLog", targets: ["AgentLog"]),
    .executable(name: "RatatoskrExportAgent", targets: ["RatatoskrExportAgent"]),
  ],
  targets: [
    .target(name: "AgentCore"),
    .target(name: "AgentLog"),
    .executableTarget(
      name: "RatatoskrExportAgent",
      dependencies: ["AgentCore", "AgentLog"]
    ),
    .testTarget(
      name: "AgentCoreTests",
      dependencies: ["AgentCore"]
    ),
    .testTarget(
      name: "AgentLogTests",
      dependencies: ["AgentLog"]
    ),
    .testTarget(
      name: "RatatoskrExportAgentTests",
      dependencies: ["RatatoskrExportAgent", "AgentCore"]
    ),
  ]
)
