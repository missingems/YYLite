// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YYLite",
    platforms: [.iOS(.v12), .macOS(.v10_15), .tvOS(.v12), .watchOS(.v5), .visionOS(.v1)],
    products: [
        .library(name: "YYLite", targets: ["YYLite"]),
    ],
    targets: [
        // Vendored yyjson 0.13.0 + size patch (patches/yyjson-size-opt.patch), read-only build,
        // extern symbols renamed yylite_* so it can coexist with another yyjson in the same app.
        .target(
            name: "CYYJSON",
            cSettings: [
                .define("YYJSON_DISABLE_WRITER", to: "1"),
                .define("YYJSON_DISABLE_UTILS", to: "1"),
                .define("YYJSON_DISABLE_INCR_READER", to: "1"),
                .define("YYJSON_DISABLE_NON_STANDARD", to: "1"),
                .define("YYJSON_DISABLE_FAST_FP_CONV", to: "1"),
                .define("YYJSON_DISABLE_FILE", to: "1"),
                .define("YYJSON_SIZE_OPT", to: "1"),
                .define("YYJSON_SIZE_OPT_NO_MSG", to: "1"),
            ]
        ),
        .target(name: "YYLite", dependencies: ["CYYJSON"]),
        .testTarget(name: "YYLiteTests", dependencies: ["YYLite", "CYYJSON"]),
        .testTarget(name: "GeneratedExampleTests", dependencies: ["YYLite"]),
    ]
)

// Objective-C API (Apple platforms only): same yyjson reader + same C writer core, no Swift involved.
// Manifests are evaluated on the build host, and every Apple-platform build runs on macOS.
#if os(macOS)
package.products.append(.library(name: "YYLiteObjC", targets: ["YYLiteObjC"]))
package.targets.append(contentsOf: [
    .target(name: "YYLiteObjC", dependencies: ["CYYJSON"]),
    .testTarget(name: "YYLiteObjCTests", dependencies: ["YYLiteObjC"]),
])
#endif
