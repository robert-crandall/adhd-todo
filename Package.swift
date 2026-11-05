// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tasks",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "TasksCore", targets: ["TasksCore"]),
        .executable(name: "TasksApp", targets: ["TasksApp"]),
        .executable(name: "tasks-mcp", targets: ["TasksMCP"])
    ],
    targets: [
        .target(
            name: "TasksCore",
            path: "Sources/TasksCore"
        ),
        .executableTarget(
            name: "TasksApp",
            dependencies: ["TasksCore"],
            path: "Sources/TasksApp"
        ),
        .executableTarget(
            name: "TasksMCP",
            dependencies: ["TasksCore"],
            path: "Sources/TasksMCP"
        ),
        .testTarget(
            name: "TasksCoreTests",
            dependencies: ["TasksCore", "TasksMCP"],
            path: "Tests/TasksCoreTests"
        )
    ]
)
