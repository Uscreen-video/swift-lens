// swift-tools-version: 5.9

import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "swift-lens",
  platforms: [
    .iOS(.v13),
    .macOS(.v10_15),
    .tvOS(.v13),
    .watchOS(.v6),
  ],
  products: [
    .library(name: "SwiftLens",targets: ["SwiftLens"]),
    .library(name: "LensMacros", targets: ["LensMacros"]),
  ],
  dependencies: [
    .package(url: "https://github.com/google/swift-benchmark", from: "0.1.0"),
    .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-macro-testing", from: "0.2.0"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
  ],
  targets: [
    .target(
      name: "SwiftLens",
      dependencies: [
        "LensMacros",
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
      ]
    ),
    .testTarget(
      name: "SwiftLensTests",
      dependencies: ["SwiftLens"]
    ),
    .target(
      name: "LensMacros",
      dependencies: [
        "LensMacrosPlugin",
        .product(name: "XCTestDynamicOverlay", package: "xctest-dynamic-overlay"),
      ]
    ),
    .macro(
      name: "LensMacrosPlugin",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "LensMacrosPluginTests",
      dependencies: [
        "LensMacrosPlugin",
        .product(name: "MacroTesting", package: "swift-macro-testing"),
      ]
    ),
    .executableTarget(
      name: "swift-lens-benchmark",
      dependencies: [
        "SwiftLens",
        .product(name: "Benchmark", package: "swift-benchmark"),
      ]
    ),
  ]
)
