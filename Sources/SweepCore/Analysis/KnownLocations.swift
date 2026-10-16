import Foundation

enum KnownLocations {
    static let developerCacheNames: Set<String> = [
        "Homebrew", "Yarn", "pip", "pip-tools", "pypoetry", "CocoaPods", "pnpm", "node-gyp", "ms-playwright",
        "ms-playwright-go", "Cypress", "JetBrains", "go-build", "gopls", "typescript", "electron", "electron-builder",
        "com.microsoft.VSCode.ShipIt", "com.github.Electron.ShipIt", "deno", "org.swift.swiftpm", "composer", "mise",
        "uv", "golangci-lint", "bazel", "prisma", "puppeteer", "node", "npm", "SwiftLint", "org.carthage.CarthageKit",
        "carthage", "com.todesktop.230313mzl4w4u92.ShipIt", "rustup", "sccache", "ccache", "cargo",
        "gradle", "Bun", "bun", "nextjs-nodejs", "turbo", "esbuild", "vite", "buf", "helm", "pre-commit",
    ]

    static let xcodeCacheNames: Set<String> = [
        "com.apple.dt.Xcode", "com.apple.dt.instruments", "com.apple.dt.XCPGDeviceSupport", "com.apple.dt.SKAgent",
    ]

    static let chromiumCacheFolderNames: Set<String> = [
        "Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache", "GrShaderCache",
        "ShaderCache", "CacheStorage", "CachedData", "CachedExtensionVSIXs", "CachedProfilesData", "Crashpad",
        "component_crx_cache", "extensions_crx_cache", "optimization_guide_model_store", "Shared Dictionary",
    ]

    struct DeveloperCache {
        let relativePath: String
        let title: String
        let safety: Safety
        let recommended: Bool
        let detail: String
    }

    static let developerCaches: [DeveloperCache] = [
        .init(relativePath: ".npm/_cacache", title: "npm cache", safety: .safe, recommended: true, detail: "npm downloads packages again when needed"),
        .init(relativePath: ".npm/_npx", title: "npx cache", safety: .safe, recommended: true, detail: "Packages fetched by npx"),
        .init(relativePath: ".npm/_logs", title: "npm logs", safety: .safe, recommended: true, detail: "Old npm debug logs"),
        .init(relativePath: ".yarn/berry/cache", title: "Yarn Berry cache", safety: .safe, recommended: true, detail: "Yarn downloads packages again when needed"),
        .init(relativePath: ".pnpm-store", title: "pnpm store", safety: .safe, recommended: true, detail: "Run pnpm install to restore packages"),
        .init(relativePath: "Library/pnpm/store", title: "pnpm store", safety: .safe, recommended: true, detail: "Run pnpm install to restore packages"),
        .init(relativePath: ".bun/install/cache", title: "Bun cache", safety: .safe, recommended: true, detail: "Bun downloads packages again when needed"),
        .init(relativePath: ".gradle/caches", title: "Gradle caches", safety: .safe, recommended: true, detail: "Gradle downloads dependencies again on the next build"),
        .init(relativePath: ".gradle/wrapper/dists", title: "Gradle wrapper distributions", safety: .safe, recommended: true, detail: "Old Gradle versions; the wrapper downloads the one it needs"),
        .init(relativePath: ".gradle/daemon", title: "Gradle daemon logs", safety: .safe, recommended: true, detail: "Logs written by Gradle daemons"),
        .init(relativePath: ".m2/repository", title: "Maven repository", safety: .review, recommended: false, detail: "Maven downloads artifacts again; local-only installs are lost"),
        .init(relativePath: ".ivy2/cache", title: "Ivy cache", safety: .safe, recommended: true, detail: "SBT / Ivy dependency cache"),
        .init(relativePath: ".cargo/registry/cache", title: "Cargo registry cache", safety: .safe, recommended: true, detail: "Downloaded crate archives"),
        .init(relativePath: ".cargo/registry/src", title: "Cargo registry sources", safety: .safe, recommended: true, detail: "Unpacked crate sources; Cargo unpacks them again"),
        .init(relativePath: ".cargo/git/checkouts", title: "Cargo git checkouts", safety: .safe, recommended: true, detail: "Git dependencies; Cargo fetches them again"),
        .init(relativePath: "go/pkg/mod", title: "Go module cache", safety: .review, recommended: false, detail: "Go downloads modules again on the next build"),
        .init(relativePath: ".cocoapods/repos", title: "CocoaPods spec repos", safety: .safe, recommended: true, detail: "CocoaPods uses the CDN by default"),
        .init(relativePath: ".nuget/packages", title: "NuGet packages", safety: .review, recommended: false, detail: "NuGet restores packages on the next build"),
        .init(relativePath: ".composer/cache", title: "Composer cache", safety: .safe, recommended: true, detail: "PHP Composer download cache"),
        .init(relativePath: ".pub-cache", title: "Dart pub cache", safety: .review, recommended: false, detail: "Flutter / Dart packages; pub get restores them"),
        .init(relativePath: ".dartServer", title: "Dart analysis server cache", safety: .safe, recommended: true, detail: "The analyzer rebuilds it"),
        .init(relativePath: ".android/cache", title: "Android SDK cache", safety: .safe, recommended: true, detail: "Android tools download cache"),
        .init(relativePath: ".android/avd", title: "Android emulators", safety: .review, recommended: false, detail: "Virtual devices and their data"),
        .init(relativePath: ".conda/pkgs", title: "Conda package cache", safety: .safe, recommended: true, detail: "Downloaded Conda packages"),
        .init(relativePath: "miniconda3/pkgs", title: "Miniconda package cache", safety: .safe, recommended: true, detail: "Downloaded Conda packages"),
        .init(relativePath: "anaconda3/pkgs", title: "Anaconda package cache", safety: .safe, recommended: true, detail: "Downloaded Conda packages"),
        .init(relativePath: "opt/anaconda3/pkgs", title: "Anaconda package cache", safety: .safe, recommended: true, detail: "Downloaded Conda packages"),
        .init(relativePath: ".nvm/.cache", title: "nvm download cache", safety: .safe, recommended: true, detail: "Node.js archives nvm downloaded"),
        .init(relativePath: ".node-gyp", title: "node-gyp headers", safety: .safe, recommended: true, detail: "Node headers for native modules"),
        .init(relativePath: ".electron-gyp", title: "electron-gyp headers", safety: .safe, recommended: true, detail: "Electron headers for native modules"),
        .init(relativePath: ".terraform.d/plugin-cache", title: "Terraform plugin cache", safety: .safe, recommended: true, detail: "Terraform downloads providers again"),
        .init(relativePath: ".platformio/.cache", title: "PlatformIO cache", safety: .safe, recommended: true, detail: "PlatformIO download cache"),
        .init(relativePath: ".expo", title: "Expo cache", safety: .review, recommended: false, detail: "Expo CLI state and caches"),
        .init(relativePath: ".vscode/extensions/.obsolete", title: "Old VS Code extensions", safety: .safe, recommended: true, detail: "Extensions VS Code marked obsolete"),
        .init(relativePath: "Library/Android/sdk/system-images", title: "Android system images", safety: .review, recommended: false, detail: "Emulator images; the SDK Manager downloads them again"),
        .init(relativePath: ".rustup/downloads", title: "rustup downloads", safety: .safe, recommended: true, detail: "Partial toolchain downloads"),
        .init(relativePath: ".rustup/tmp", title: "rustup temporary files", safety: .safe, recommended: true, detail: "Temporary toolchain files"),
        .init(relativePath: ".ollama/models/blobs/partial", title: "Ollama partial downloads", safety: .safe, recommended: true, detail: "Unfinished model downloads"),
    ]

    static let reviewDotCacheNames: Set<String> = ["huggingface", "torch", "whisper", "lm-studio", "ollama", "models", "keras", "kagglehub"]

    struct ArtifactRule {
        let name: String
        let requiredMarkers: ProjectMarkers?
        let safety: Safety
        let staleDays: Int
        let restoreHint: String
        let isTinyCache: Bool

        init(_ name: String, markers: ProjectMarkers?, safety: Safety = .safe, staleDays: Int = 14, restoreHint: String, tiny: Bool = false) {
            self.name = name
            self.requiredMarkers = markers
            self.safety = safety
            self.staleDays = staleDays
            self.restoreHint = restoreHint
            self.isTinyCache = tiny
        }

        func matches(_ markers: ProjectMarkers) -> Bool {
            guard let requiredMarkers else { return true }
            return !markers.isDisjoint(with: requiredMarkers)
        }
    }

    static let artifactRules: [String: [ArtifactRule]] = {
        let rules: [ArtifactRule] = [
            .init("node_modules", markers: .nodePackage, staleDays: 30, restoreHint: "Run npm / yarn / pnpm install to restore"),
            .init(".next", markers: .nodePackage, restoreHint: "Next.js rebuilds it on the next build"),
            .init(".nuxt", markers: .nodePackage, restoreHint: "Nuxt rebuilds it on the next build"),
            .init(".output", markers: .nodePackage, restoreHint: "Nuxt / Nitro rebuilds it"),
            .init(".svelte-kit", markers: .nodePackage, restoreHint: "SvelteKit rebuilds it"),
            .init(".turbo", markers: .nodePackage, restoreHint: "Turborepo cache; rebuilt on the next run"),
            .init(".parcel-cache", markers: .nodePackage, restoreHint: "Parcel rebuilds it"),
            .init(".angular", markers: .nodePackage, restoreHint: "Angular CLI cache; rebuilt on the next build"),
            .init(".docusaurus", markers: .nodePackage, restoreHint: "Docusaurus rebuilds it"),
            .init(".vercel", markers: .nodePackage, safety: .review, restoreHint: "Vercel build output and project link"),
            .init(".nx", markers: .nodePackage, restoreHint: "Nx cache; rebuilt on the next run"),
            .init(".cache", markers: .nodePackage, restoreHint: "Tool cache inside the project"),
            .init(".nyc_output", markers: .nodePackage, restoreHint: "Coverage data; tests make it again"),
            .init("coverage", markers: .nodePackage, safety: .review, restoreHint: "Coverage report; tests make it again"),
            .init("target", markers: [.cargo, .maven], restoreHint: "cargo build / mvn package rebuilds it"),
            .init("Pods", markers: .cocoaPods, staleDays: 30, restoreHint: "Run pod install to restore"),
            .init(".build", markers: .swiftPackage, restoreHint: "swift build rebuilds it"),
            .init("DerivedData", markers: nil, restoreHint: "Xcode rebuilds it"),
            .init(".gradle", markers: .gradle, restoreHint: "Gradle rebuilds it"),
            .init("build", markers: [.gradle, .flutter], restoreHint: "The next build makes it again"),
            .init(".dart_tool", markers: .flutter, restoreHint: "flutter pub get restores it"),
            .init(".terraform", markers: .terraform, safety: .review, restoreHint: "terraform init restores providers and modules"),
            .init("_build", markers: .elixir, restoreHint: "mix compile rebuilds it"),
            .init("deps", markers: .elixir, restoreHint: "mix deps.get restores it"),
            .init("cmake-build-debug", markers: .cmake, restoreHint: "CMake rebuilds it"),
            .init("cmake-build-release", markers: .cmake, restoreHint: "CMake rebuilds it"),
            .init("obj", markers: .dotnet, restoreHint: "dotnet build rebuilds it"),
            .init(".venv", markers: .python, safety: .review, staleDays: 60, restoreHint: "Recreate with python -m venv and pip install"),
            .init("venv", markers: .python, safety: .review, staleDays: 60, restoreHint: "Recreate with python -m venv and pip install"),
            .init(".tox", markers: .python, restoreHint: "tox recreates it"),
            .init(".nox", markers: .python, restoreHint: "nox recreates it"),
            .init("__pycache__", markers: nil, restoreHint: "Python writes bytecode again", tiny: true),
            .init(".pytest_cache", markers: nil, restoreHint: "pytest recreates it", tiny: true),
            .init(".mypy_cache", markers: nil, restoreHint: "mypy recreates it", tiny: true),
            .init(".ruff_cache", markers: nil, restoreHint: "Ruff recreates it", tiny: true),
            .init(".hypothesis", markers: nil, restoreHint: "Hypothesis recreates it", tiny: true),
            .init(".ipynb_checkpoints", markers: nil, safety: .review, restoreHint: "Jupyter autosave copies", tiny: true),
        ]
        return Dictionary(grouping: rules, by: \.name)
    }()
}
