// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Hum",
  platforms: [.macOS(.v15)],
  targets: [
    .executableTarget(
      name: "Hum",
      path: "Sources/Hum",
      linkerSettings: [.linkedFramework("IOKit")]
    )
  ],
  swiftLanguageModes: [.v5]
)
