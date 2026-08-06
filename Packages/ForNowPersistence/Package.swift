// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "ForNowPersistence",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "ForNowPersistence", targets: ["ForNowPersistence"]),
    .executable(name: "PersistenceCrashWorker", targets: ["PersistenceCrashWorker"]),
  ],
  dependencies: [
    .package(path: "../ForNowCore"),
    .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
  ],
  targets: [
    .target(
      name: "ForNowPersistence",
      dependencies: [
        "ForNowCore",
        .product(name: "GRDB", package: "GRDB.swift"),
      ]
    ),
    .executableTarget(
      name: "PersistenceCrashWorker",
      dependencies: ["ForNowCore", "ForNowPersistence"]
    ),
    .testTarget(
      name: "ForNowPersistenceTests",
      dependencies: [
        "ForNowCore",
        "ForNowPersistence",
        .product(name: "GRDB", package: "GRDB.swift"),
      ]
    ),
  ],
  swiftLanguageModes: [.v6]
)
