// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ctrlv",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "ctrlv", targets: ["ctrlv"])],
    targets: [
        .executableTarget(name: "ctrlv"),
        .testTarget(name: "ctrlvTests", dependencies: ["ctrlv"])
    ]
)
