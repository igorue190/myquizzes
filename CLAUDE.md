# CLAUDE.md

Markwise — a **local-first, offline iOS app** that turns Markdown (`.md`) study files
into interactive quizzes (Training + exam-style Exam modes). No backend, no sign-in.

Detailed conventions live in **`.claude/rules/`** — read the relevant file before
working in an area. This file is the always-loaded summary of the essentials.

## Must-not-break essentials

- **Toolchain:** Swift 6.1, **Swift 6 language mode** (strict concurrency), iOS 18 min
  on the **iOS 26 SDK**. This machine's CLT is corrupted — run
  `export DEVELOPER_DIR=~/Downloads/Xcode.app/Contents/Developer` before any
  `swift`/`xcodebuild`. → `.claude/rules/60-build-toolchain.md`
- **Layering is a hard rule.** `CoreModels` (pure, Foundation-only) →
  `MarkdownParser`/`QuizEngine`/`Statistics` (pure) → `Persistence` → `DesignSystem` →
  feature packages → `AppFeature` (composition root). **A feature package never
  depends on another feature** — share via a core package. Keep the pure core free of
  SwiftUI/SwiftData/UIKit. → `.claude/rules/10-architecture.md`
- **Quiz logic lives in `QuizEngine`,** not in views or view models. Views hold a
  `@State` view model, send intents, render results — no business logic.
- **Concurrency:** domain types are `Sendable` value types; view models are
  `@MainActor @Observable final class`; repositories are `actor`s behind `Sendable`
  protocols in `CoreModels`. Don't reach for `@unchecked Sendable` to silence errors.
  → `.claude/rules/20-concurrency.md`
- **UI uses DesignSystem tokens only** (`Spacing`/`Radius`/`Typography`/`ColorTokens`/
  `Motion`) — no hard-coded numbers/colors. All glass goes through `glassSurface(_:)`;
  gate iOS 26 APIs with `#available` and honor Reduce Transparency/Motion. →
  `.claude/rules/40-design-system.md`
- **Tests use swift-testing** (`import Testing`, `@Suite`, `@Test`, `#expect`) — **not
  XCTest**. The pure core carries the heaviest coverage; engine tests rely on the
  seeded RNG for deterministic assertions. → `.claude/rules/50-testing.md`
- **Every file opens with a header comment** (filename, package, purpose-in-the-
  architecture). Mark the public surface `public` with an explicit `public init`. →
  `.claude/rules/30-domain-models.md`, `.claude/rules/70-code-style.md`

## Build / test

```bash
export DEVELOPER_DIR=~/Downloads/Xcode.app/Contents/Developer   # once per shell
swift test --package-path Packages/QuizEngine                   # pure-core tests
swift run myquizzes Samples/AZ-900.md                           # CLI demo
xcodebuild -project Markwise.xcodeproj -scheme Markwise \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

See `README.md` for install/launch-in-simulator details (bundle id `com.markwise.app`).
