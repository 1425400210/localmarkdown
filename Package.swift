// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalMarkdown",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LocalMarkdown", targets: ["LocalMarkdown"])],
    targets: [
        .executableTarget(name: "LocalMarkdown", resources: [.copy("Resources/Editor")]),
        .testTarget(name: "LocalMarkdownTests", dependencies: ["LocalMarkdown"])
    ]
)
