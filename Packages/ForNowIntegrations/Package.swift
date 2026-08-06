// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "ForNowIntegrations",
  platforms: [.macOS(.v14)],
  products: [.library(name: "ForNowIntegrations", targets: ["ForNowIntegrations"])],
  dependencies: [
    .package(path: "../ForNowCore")
  ],
  targets: [.target(name: "ForNowIntegrations", dependencies: ["ForNowCore"])],
  swiftLanguageModes: [.v6]
)
