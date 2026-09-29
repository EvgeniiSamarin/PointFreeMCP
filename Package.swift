// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "PointFreeMCP",
  platforms: [.macOS(.v26)],
  products: [
    .executable(name: "pointfree-mcp", targets: ["PointFreeMCP"]),
    .library(name: "PointFreeKit", targets: ["PointFreeKit"]),
  ],
  dependencies: [
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
    .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.13.9"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies.git", from: "1.17.1"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.15.1"),
  ],
  targets: [
    .target(
      name: "PointFreeKit",
      dependencies: [
        .product(name: "SwiftSoup", package: "SwiftSoup"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesMacros", package: "swift-dependencies"),
      ]
    ),
    .executableTarget(
      name: "PointFreeMCP",
      dependencies: [
        "PointFreeKit",
        .product(name: "MCP", package: "swift-sdk"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "Logging", package: "swift-log"),
      ]
    ),
    .testTarget(
      name: "PointFreeKitTests",
      dependencies: [
        "PointFreeKit",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      resources: [.copy("Fixtures")]
    ),
  ],
  swiftLanguageModes: [.v6]
)
