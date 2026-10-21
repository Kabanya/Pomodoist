// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "multiview_desktop",
  platforms: [
    .macOS("10.14"),
  ],
  products: [
    .library(name: "multiview-desktop", targets: ["multiview_desktop"]),
  ],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework"),
  ],
  targets: [
    .target(
      name: "multiview_desktop",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework"),
      ]
    ),
  ]
)
