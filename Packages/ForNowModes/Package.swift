// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "ForNowModes",
  platforms: [.macOS(.v14)],
  products: [.library(name: "ForNowModes", targets: ["ForNowModes"])],
  dependencies: [
    .package(path: "../ForNowCore")
  ],
  targets: [.target(name: "ForNowModes", dependencies: ["ForNowCore"])],
  swiftLanguageModes: [.v6]
)
