// swift-tools-version: 6.0
import PackageDescription

// This Package.swift drives the cmark-gfm dependency and test-only SPM targets.
// The main app target lives in MarkView.xcodeproj.
let package = Package(
    name: "MarkView",
    platforms: [.macOS(.v15)],
    dependencies: [
        // cmark-gfm: vendored C target added in M2.1; swap this placeholder
        // for a real URL once vendoring is done.
    ],
    targets: [
        .target(
            name: "MarkViewCore",
            path: "Sources",
            sources: [
                "Model/DocumentKey.swift",
                "Render/DiffAnnotator.swift",
                "Render/HeadingSlugger.swift",
                "Render/LinkClassifier.swift",
                "Render/HTMLSanitizer.swift",
                "Render/LocalImagePolicy.swift",
                "Render/LocalImageRewriter.swift",
            ]
        ),
        .testTarget(
            name: "MarkViewTests",
            dependencies: ["MarkViewCore"],
            path: "Tests",
            exclude: ["GoldenRendererTests.swift"]  // requires Xcode test bundle (CmarkGFM + app host)
        ),
    ]
)
