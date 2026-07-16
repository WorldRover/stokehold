// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "stokehold",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "stokehold")
    ]
)
