// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AppReportKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(name: "AppReportKit", targets: ["AppReportKit"]),
        .library(name: "AppReportKitUI", targets: ["AppReportKitUI"])
    ],
    targets: [
        .target(name: "AppReportKit"),
        .target(
            name: "AppReportKitUI",
            dependencies: ["AppReportKit"]
        ),
        .testTarget(
            name: "AppReportKitTests",
            dependencies: ["AppReportKit"]
        ),
        .testTarget(
            name: "AppReportKitUITests",
            dependencies: ["AppReportKitUI", "AppReportKit"]
        )
    ]
)

