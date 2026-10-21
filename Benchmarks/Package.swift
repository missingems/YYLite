// swift-tools-version: 5.9
// Benchmarks / size measurements for YYLite with 50 generated models. Not part of the library.
import PackageDescription
let package = Package(
    name: "YYLiteBenchmarks",
    platforms: [.macOS(.v12), .iOS(.v15)],
    dependencies: [.package(path: "..")],
    targets: [
        .target(name: "Codable50"),
        .target(name: "Codable50D"),
        .target(name: "Models50", dependencies: [.product(name: "YYLite", package: "YYLite")]),
        .target(name: "Models50Loop", dependencies: [.product(name: "YYLite", package: "YYLite")]),
        .target(name: "Models50S", dependencies: [.product(name: "YYLite", package: "YYLite")]),  // same, as structs
        .target(name: "Compare50", dependencies: ["Codable50", "Models50"]),
        .target(name: "Compare50S", dependencies: ["Codable50", "Models50S"]),
        .executableTarget(name: "Bench50", dependencies: ["Codable50", "Models50", "Models50Loop", "Models50S", "Compare50", "Compare50S"]),
        .executableTarget(name: "alloc50", dependencies: ["Codable50", "Models50", "Models50S", "Compare50"]),
        .testTarget(name: "Bench50Tests", dependencies: ["Codable50", "Models50", "Models50S", "Compare50", "Compare50S"]),
        .executableTarget(name: "prof50", dependencies: ["Models50", "Compare50"]),
        // size probes (see measure.sh)
        .executableTarget(name: "sz_empty"),
        .executableTarget(name: "sz_codable_dec", dependencies: ["Codable50"]),
        .executableTarget(name: "sz_codable_both", dependencies: ["Codable50"]),
        .executableTarget(name: "sz_codableD_dec", dependencies: ["Codable50D"]),
        .executableTarget(name: "sz_lite_dec", dependencies: ["Models50"]),
        .executableTarget(name: "sz_lite_both", dependencies: ["Models50"]),
        .executableTarget(name: "sz_loop_dec", dependencies: ["Models50Loop"]),
        .executableTarget(name: "sz_struct_dec", dependencies: ["Models50S"]),
        .executableTarget(name: "sz_struct_both", dependencies: ["Models50S"]),
        .executableTarget(name: "sz_lite_core_both", dependencies: [.product(name: "YYLite", package: "YYLite")]),
    ]
)
