# Architecture & Package Layering

The codebase is a strict, layered SPM monorepo. **The dependency direction is a hard
rule, not a guideline** — it's what keeps the correctness-critical core testable on a
plain toolchain and the UI compile-checked package-by-package.

## The layers (low → high)

```
CoreModels        pure value types + repository protocols + seeded RNG. NO deps but Foundation.
  ├─ MarkdownParser   .md → ParsedQuiz. Deps: CoreModels + apple/swift-markdown.
  ├─ QuizEngine       session state machine + scoring. Deps: CoreModels only.
  └─ Statistics       aggregates [SessionRecord]. Deps: CoreModels.
Persistence       SwiftData + file store implementing CoreModels' repo protocols.
DesignSystem      Liquid Glass components, tokens, theme. SwiftUI. No domain deps.
*Feature packages QuizFeature, LibraryFeature, ImportFeature, StatsFeature,
                  ResultsFeature, ProfileFeature — each: core packages + DesignSystem.
AppFeature        the composition root: root TabView + glue. Depends on everything.
Markwise.xcodeproj  thin @main shell → AppFeature.RootView.
```

## Rules you must not break

1. **A feature package never depends on another feature package.** Features depend
   only on the core packages (`CoreModels`, `QuizEngine`, `MarkdownParser`,
   `Statistics`, `Persistence`) and `DesignSystem`. Cross-feature wiring happens in
   `AppFeature`. If two features need to share something, it belongs in a core package.

2. **The pure core stays pure.** `CoreModels`, `MarkdownParser`, `QuizEngine`, and
   `Statistics` import **only Foundation** (plus swift-markdown in the parser). No
   SwiftUI, no SwiftData, no UIKit. These build and `swift test` on any platform and
   carry the heaviest unit-test coverage.

3. **Quiz rules live in the engine, not the UI.** Selection, scoring, shuffling, and
   session state transitions belong in `QuizEngine`. Views and view models forward
   intents and render results — they never re-implement quiz logic.

4. **Persistence is reached only through protocols in `CoreModels`**
   (`SessionRepository`, `LibraryRepository`, `ProfileRepository`). Features depend on
   the protocol; concrete SwiftData actors live in `Persistence` and are injected at
   the `AppFeature` composition root. Use the `InMemory*` actors for previews/tests.

5. **Adding a package** means: create `Packages/<Name>/` with its own `Package.swift`
   (`swift-tools-version: 6.1`), declare `platforms`, add a `.testTarget`, set
   `swiftSettings: [.swiftLanguageMode(.v6)]` on iOS/UI targets, then wire it into
   `AppFeature/Package.swift` and the Xcode project — not into a sibling feature.

## View-model boundary

Each screen has one `@MainActor @Observable` view model that **owns a value-type
state object** from the engine (e.g. `QuizSession`), forwards user intents to it, and
exposes display-ready computed state — including the mapping from domain enums to
`DesignSystem` view enums (see `QuizSessionViewModel`). The SwiftUI `View` holds
`@State private var model`, reads it, and sends intents. **No business logic in views.**
Side effects the feature shouldn't own (e.g. persisting a result) are surfaced as
closures like `onFinish` so the feature stays dependency-free.
