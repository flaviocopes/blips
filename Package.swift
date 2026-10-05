// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "Blips",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "BlipsCore", targets: ["BlipsCore"]),
    .executable(name: "BlipsApp", targets: ["BlipsApp"]),
    .executable(name: "blips", targets: ["BlipsCLI"])
  ],
  targets: [
    .target(name: "BlipsCore"),
    .executableTarget(
      name: "BlipsApp",
      dependencies: ["BlipsCore"]
    ),
    .executableTarget(
      name: "BlipsCLI",
      dependencies: ["BlipsCore"]
    ),
    .testTarget(
      name: "BlipsCoreTests",
      dependencies: ["BlipsCore"]
    )
  ]
)
