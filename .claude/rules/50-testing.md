# Testing

The project uses **swift-testing** (Apple's `Testing` framework), **not XCTest**. New
tests must follow the same style.

## Conventions

- `import Testing`, `@testable import <Package>`, plus `import CoreModels` for fixtures.
- Group tests in a `@Suite("human description") struct`.
- Each test is a `@Test("describes the behavior")` method (a plain `func`, often
  non-async) using `#expect(...)` for assertions (and `#require` when a later step
  depends on the value).
- Put fixture builders as `private` free functions at the top of the file
  (`private func choice(...)`, `private func pool(...)`). Keep them small and reusable.

## What must stay testable

- **The pure core carries the heaviest coverage.** `CoreModels`, `MarkdownParser`,
  `QuizEngine`, `Statistics`, and `Persistence` each have a `.testTarget` and run via
  `swift test` on a plain toolchain. Don't add UI/IO dependencies that break that.
- **Determinism is the test strategy.** The engine is seeded (`SeededGenerator`), so
  tests assert exact outcomes: same seed ⇒ same selection/shuffle; different seed ⇒
  different. Preserve seed-threading so new engine behavior stays assertable this way.
- **Repositories are tested against the `InMemory*` actors** (in CoreModels) and the
  real SwiftData actors (in Persistence) through the same protocol.
- **iOS/feature packages** (`DesignSystem`, `QuizFeature`, `LibraryFeature`,
  `StatsFeature`, `ProfileFeature`) test on a Simulator via `xcodebuild test`. Feature
  tests target the view model, not pixels (plus a DesignSystem snapshot smoke test).

## Running tests

```bash
# pure packages (any macOS toolchain)
swift test --package-path Packages/QuizEngine

# a feature/iOS package (Simulator)
( cd Packages/QuizFeature && xcodebuild test -scheme QuizFeature \
    -destination 'platform=iOS Simulator,name=iPhone 16' )
```

CI (`.github/workflows/ci.yml`) runs the pure packages with `swift test`, the iOS
packages/app on a Simulator, and the `myquizzes` CLI against `Samples/AZ-900.md`.
Mirror that split when verifying changes locally.
