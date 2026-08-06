// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "ForNowWindowing",
  platforms: [.macOS(.v14)],
  products: [.library(name: "ForNowWindowing", targets: ["ForNowWindowing"])],
  dependencies: [
    .package(path: "../ForNowCore"),
    .package(
      url: "https://github.com/sindresorhus/KeyboardShortcuts.git",
      exact: "1.10.0"
    ),
  ],
  targets: [
    .target(
      name: "ForNowWindowing",
      dependencies: [
        "ForNowCore",
        .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
      ]
    )
  ],
  swiftLanguageModes: [.v6]
)
