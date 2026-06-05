// swift-tools-version: 6.0
import PackageDescription

// Vendored cmark-gfm 0.29.0.gfm.13 C target.
// This is the same parser GitHub uses for Markdown rendering.
let package = Package(
    name: "CmarkGFM",
    products: [
        .library(name: "CmarkGFM", targets: ["CmarkGFM"]),
    ],
    targets: [
        .target(
            name: "CmarkGFM",
            path: "Sources/CmarkGFM",
            exclude: [
                "module.modulemap",
            ],
            publicHeadersPath: ".",
            cSettings: [
                .define("CMARK_STATIC_DEFINE"),
                .define("CMARK_GFM_STATIC_DEFINE"),
            ]
        ),
    ]
)
