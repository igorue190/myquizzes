# Build & Toolchain

## Toolchain requirement (this machine)

This machine's Command Line Tools are corrupted, so **builds must use the Xcode
toolchain explicitly**. Run once per shell before any `swift`/`xcodebuild` command:

```bash
export DEVELOPER_DIR=~/Downloads/Xcode.app/Contents/Developer
```

You need **Xcode 26+** (for the iOS 26 SDK / Liquid Glass). Pure packages can build on
a plain macOS toolchain in principle, but on this machine they still need the Xcode
`DEVELOPER_DIR` because the default CLT is broken.

## Build & run commands

```bash
# Pure-core tests (no iOS SDK needed)
swift test --package-path Packages/CoreModels
swift test --package-path Packages/MarkdownParser
swift test --package-path Packages/QuizEngine

# CLI demo: parse a quiz → run a session → print a score report
swift run myquizzes                  # bundled Samples/AZ-900.md
swift run myquizzes path/to/quiz.md  # your own file

# iOS app (build for Simulator)
xcodebuild -project Markwise.xcodeproj -scheme Markwise \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

To install/launch in a booted simulator, follow the recipe in `README.md` (§Building).
The bundle id is `com.markwise.app`. The `MARKWISE_UITEST_SCREEN` env var
(`practice` / `runner`) deep-links the app to a screen for snapshots:
`SIMCTL_CHILD_MARKWISE_UITEST_SCREEN=runner xcrun simctl launch "$UDID" com.markwise.app`.

## Repo layout notes

- `Packages/` holds **our own local source packages** and is intentionally tracked;
  only their nested `.build/` output is gitignored. Don't gitignore `Packages/` itself.
- The Xcode project target is a thin `@main` shell (`App/MarkwiseApp.swift`) — real UI
  lives in `AppFeature`. Add screens to feature packages, not the app target.
- Prefer adding code to a package (compile-checked + testable in isolation) over the
  Xcode app target.
