// swift-tools-version: 5.10
//
// Root package manifest for AppReportKit.
// The implementation lives under `swift/` and is wired via explicit target paths.
import PackageDescription

let package = Package(
    name: "AppReportKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(name: "AppReportKit", targets: ["AppReportKit"]),
        .library(name: "AppReportKitUI", targets: ["AppReportKitUI"]),
        .library(name: "AppReportKitDiagnostics", targets: ["AppReportKitDiagnostics"])
    ],
    targets: [
        .target(
            name: "AppReportKit",
            path: "swift/Sources/AppReportKit"
        ),
        .target(
            name: "AppReportKitUI",
            dependencies: ["AppReportKit"],
            path: "swift/Sources/AppReportKitUI"
        ),
        .target(
            name: "AppReportKitDiagnostics",
            dependencies: ["AppReportKit"],
            path: "swift/Sources/AppReportKitDiagnostics"
        ),
        .testTarget(
            name: "AppReportKitTests",
            dependencies: ["AppReportKit"],
            path: "swift/Tests/AppReportKitTests"
        ),
        .testTarget(
            name: "AppReportKitUITests",
            dependencies: ["AppReportKitUI", "AppReportKit"],
            path: "swift/Tests/AppReportKitUITests"
        ),
        .testTarget(
            name: "AppReportKitDiagnosticsTests",
            dependencies: ["AppReportKitDiagnostics", "AppReportKit"],
            path: "swift/Tests/AppReportKitDiagnosticsTests"
        )
    ]
)
