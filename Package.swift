// swift-tools-version:5.9
import PackageDescription

// NOTE: Rize ships as an Xcode app target (Rize.xcodeproj). This manifest is
// kept only for tooling that expects a package root. The app has NO external
// dependencies — planning is deterministic and all AI is Apple's on-device
// Foundation Models framework (system SDK, not a package).
let package = Package(
    name: "Rize",
    targets: [
        .target(name: "Rize")
    ]
)
