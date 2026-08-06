// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "ForNowCore",
  platforms: [.macOS(.v14)],
  products: [.library(name: "ForNowCore", targets: ["ForNowCore"])],
  targets: [.target(name: "ForNowCore")],
  swiftLanguageModes: [.v6]
)
