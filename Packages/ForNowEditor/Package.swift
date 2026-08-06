// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "ForNowEditor",
  platforms: [.macOS(.v14)],
  products: [.library(name: "ForNowEditor", targets: ["ForNowEditor"])],
  dependencies: [
    .package(path: "../ForNowCore"),
    .package(path: "../ForNowDesign"),
    .package(path: "../ForNowModes"),
  ],
  targets: [
    .target(
      name: "ForNowEditor",
      dependencies: ["ForNowCore", "ForNowDesign", "ForNowModes"]
    )
  ],
  swiftLanguageModes: [.v6]
)
