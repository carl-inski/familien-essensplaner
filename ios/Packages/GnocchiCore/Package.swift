// swift-tools-version: 6.1
// Die Regeln der App ohne Oberfläche: Spiele, Einkauf, Planänderungen.
// Gegenstück zu lib/*.ts der Web-App. Läuft auch ohne Xcode: `swift test`.

import PackageDescription

let package = Package(
    name: "GnocchiCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GnocchiCore", targets: ["GnocchiCore"]),
    ],
    targets: [
        .target(name: "GnocchiCore"),
        .testTarget(name: "GnocchiCoreTests", dependencies: ["GnocchiCore"]),
    ]
)
