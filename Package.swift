// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Rize",
    dependencies: [
        .package(url: "https://github.com/apple/coremltools", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "Rize",
            dependencies: [
                .product(name: "CoreML", package: "coremltools")
            ]
        ),
    ]
)
