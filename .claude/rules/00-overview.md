# Markwise — Project Rules Overview

Markwise is a **local-first iOS app** that turns Markdown (`.md`) study files into
interactive quizzes (Training + Microsoft-exam-style Exam modes). **No backend, no
sign-in, fully offline.** The full spec lives in `Markwise-iOS-Technical-Plan.md`;
these rules capture how this repo implements it.

## What this is at a glance

- **Language/toolchain:** Swift 6.1 tools, **Swift 6 language mode** (strict
  concurrency), iOS 18 deployment min built against the **iOS 26 SDK** (Liquid Glass).
- **Structure:** an SPM **multi-package monorepo** under `Packages/`. The Xcode
  project (`Markwise.xcodeproj`) is a thin `@main` shell that just presents
  `AppFeature.RootView`. A root `myquizzes` CLI exercises the pure core on a plain
  macOS toolchain.
- **UI:** SwiftUI, `@Observable` `@MainActor` view models over **value-type** domain
  models. A `DesignSystem` package owns every visual primitive.
- **Persistence:** SwiftData (`ModelActor`s) + a file store, behind repository
  protocols declared in `CoreModels`.
- **Tests:** **swift-testing** (`import Testing`, `@Suite`, `@Test`, `#expect`) —
  not XCTest.

## The rules in this directory

| File | Covers |
|---|---|
| `10-architecture.md` | Package layering and the dependency rules you must not break |
| `20-concurrency.md` | Swift 6 strict concurrency: `Sendable`, actors, `@MainActor`, `@Observable` |
| `30-domain-models.md` | Value-type domain conventions and the repository boundary |
| `40-design-system.md` | Tokens, Liquid Glass, and accessibility |
| `50-testing.md` | swift-testing conventions and what must stay testable |
| `60-build-toolchain.md` | How to build/test (incl. the `DEVELOPER_DIR` requirement) |
| `70-code-style.md` | File headers, `MARK:` sections, public-API hygiene |

When in doubt, prefer the pattern already established in the package you're editing
over introducing a new one.
