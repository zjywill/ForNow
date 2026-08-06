// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "ForNowDesign",
  platforms: [.macOS(.v14)],
  products: [.library(name: "ForNowDesign", targets: ["ForNowDesign"])],
  targets: [.target(name: "ForNowDesign")],
  swiftLanguageModes: [.v6]
)
