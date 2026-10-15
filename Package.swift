// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mpd-bar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MPDBar", targets: ["MPDBar"]),
        .executable(name: "mpdbar-probe", targets: ["MPDBarProbe"]),
    ],
    targets: [
        .target(name: "MPDBarCore"),
        .executableTarget(name: "MPDBar", dependencies: ["MPDBarCore"]),
        .executableTarget(name: "MPDBarProbe", dependencies: ["MPDBarCore"]),
    ]
)
