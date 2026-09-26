// swift-tools-version:5.10
import PackageDescription

// TarjemCore holds the platform-independent logic (text grouping, color sampling,
// Google response parsing) so it can be unit-tested anywhere, including Linux CI.
// The Tarjem app target uses AppKit / Vision / ScreenCaptureKit / Translation and
// is only built on macOS.
var products: [Product] = [
    .library(name: "TarjemCore", targets: ["TarjemCore"]),
]

var targets: [Target] = [
    .target(name: "TarjemCore"),
    .testTarget(name: "TarjemCoreTests", dependencies: ["TarjemCore"]),
]

#if os(macOS)
products.append(.executable(name: "Tarjem", targets: ["Tarjem"]))
targets.append(.executableTarget(name: "Tarjem", dependencies: ["TarjemCore"]))
#endif

let package = Package(
    name: "Tarjem",
    platforms: [.macOS("15.0")],
    products: products,
    targets: targets
)
