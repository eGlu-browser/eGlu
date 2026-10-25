// swift-tools-version:5.9
import PackageDescription

// EGLU_ENGINES_LOCAL=1 builds against the XCFramework ./build.sh just made,
// for building and testing before a release exists. Otherwise the pinned
// binary comes from the engines-<version> release on GitHub.
let ffi: Target = Context.environment["EGLU_ENGINES_LOCAL"] == "1"
    ? .binaryTarget(
        name: "EgluEnginesFFI",
        path: "build/EgluEngines.xcframework")
    : .binaryTarget(
        name: "EgluEnginesFFI",
        url: "https://github.com/eGlu-dot-apps/eGlu/releases/download/engines-0.1.0/EgluEngines.xcframework.zip",
        checksum: "5e621d4eebc3b55a283bf1fa2a0cb5d53bf81662a9554171c5f9a1235c83ab32")

let package = Package(
    name: "Engines",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Engines", targets: ["Engines"])
    ],
    targets: [
        ffi,
        .target(
            name: "Engines",
            dependencies: ["EgluEnginesFFI"],
            resources: [.copy("Licenses.txt")]),
        .testTarget(
            name: "EnginesTests",
            dependencies: ["Engines"]),
    ]
)
