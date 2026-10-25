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
        url: "https://github.com/eGlu-dot-app/eGlu/releases/download/engines-0.1.0/EgluEngines.xcframework.zip",
        checksum: "bf515cb0e5008a8d3e83493d2e67ee237e23141dfa336d4d45f2611eb7a78be1")

// Every data race Swift 6 would refuse, as a warning, and Swift 6.2's
// approachable defaults: the same settings as PadCore's.
let concurrency: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InferSendableFromCaptures"),
    .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
    .enableUpcomingFeature("DisableOutwardActorInference"),
]

let package = Package(
    name: "Engines",
    // The macOS the library's slices are built for (build.sh's
    // MACOSX_DEPLOYMENT_TARGET); an older one makes the linker warn on
    // every object file. The Mac apps need macOS 26 anyway.
    platforms: [.iOS(.v17), .macOS("26.0")],
    products: [
        .library(name: "Engines", targets: ["Engines"])
    ],
    targets: [
        ffi,
        .target(
            name: "Engines",
            dependencies: ["EgluEnginesFFI"],
            resources: [.copy("Licenses.txt")],
            swiftSettings: concurrency),
        .testTarget(
            name: "EnginesTests",
            dependencies: ["Engines"],
            swiftSettings: concurrency),
    ]
)
