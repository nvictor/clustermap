// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClustermapCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "ClustermapCore", targets: ["ClustermapCore"])],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2")],
    targets: [
        .target(name: "ClustermapCore", dependencies: [.product(name: "Yams", package: "Yams")]),
        .testTarget(name: "ClustermapCoreTests", dependencies: ["ClustermapCore"]),
    ]
)
