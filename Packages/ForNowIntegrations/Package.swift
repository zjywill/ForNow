// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "ForNowIntegrations",
  platforms: [.macOS(.v14)],
  products: [.library(name: "ForNowIntegrations", targets: ["ForNowIntegrations"])],
  dependencies: [
    .package(path: "../ForNowCore"),
    .package(
      url: "https://github.com/weichsel/ZIPFoundation.git",
      exact: "0.9.20"
    ),
  ],
  targets: [
    .target(
      name: "ForNowIntegrations",
      dependencies: [
        "ForNowCore",
        .product(name: "ZIPFoundation", package: "ZIPFoundation"),
      ]
    )
  ],
  swiftLanguageModes: [.v6]
)
