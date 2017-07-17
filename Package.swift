// swift-tools-version:4.0
import PackageDescription

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
let dependencies: [Package.Dependency] = []
#else
let dependencies: [Package.Dependency] = [.package(url: "https://github.com/Meniny/Zipper.git", .exact("1.0.2"))]
#endif

let package = Package(
    name: "Zipper",
    products: [
        .library(name: "Zipper", targets: ["Zipper"])
    ],
	dependencies: dependencies,
    targets: [
        .target(name: "Zipper"),
		.testTarget(name: "ZipperTests", dependencies: ["Zipper"])
    ]
)
