# Markwise — App Overview

> One file, two audiences. The first half is for **anyone using the app**.
> The second half is for **developers** working on the code.
> New here? Start with the [Tutorial](Tutorial.md).

Markwise turns plain **Markdown study notes into interactive quizzes and
flashcards**. It runs entirely on your iPhone — **no account, no backend, no
internet required** for the core experience. Your study files are yours: they're
just `.md` text you can edit anywhere.

---

# Part 1 — For Users

## What Markwise does

- 📝 **Write quizzes as Markdown.** A question is a heading, the answers are a
  checklist (`- [x]` is correct, `- [ ]` is wrong), and you can add an
  explanation. That's the whole format — see the [Tutorial](Tutorial.md).
- 🎯 **Practice in two modes.**
  - **Training** — immediate feedback after each question, learn as you go.
  - **Exam** — a timed, Microsoft-certification-style run; you get your score at
    the end, like the real thing.
- 📚 **Organize a Library.** Group your study files into **Categories → Topics →
  Folders** (e.g. *Azure → AZ-900 → Practice Tests*). A file can be a **quiz** or
  a **vocabulary** set.
- 🌍 **Learn vocabulary with flashcards.** Bilingual word/phrase sets become a
  swipeable flashcard deck with **spaced repetition** (a Leitner box system:
  cards you know come back less often, cards you miss come back sooner). The same
  set also powers translation quizzes.
- 📈 **Track your progress.** The Stats/History tab records every session and
  surfaces what's **due for review**, so you spend time where it helps most.
- 👤 **Make it yours.** Set your name, and **back up / restore** your whole
  library and history to a file.

## Optional AI features (bring your own key)

Markwise works fully offline. If you *want* a few smart extras, you can turn on
AI features in **Profile** and paste your own **Claude API key** (stored securely
in the iOS Keychain on your device). Then you can:

- 💡 **Explain a missed answer** — ask for a plain-language explanation of why you
  got a question wrong.
- ✨ **Generate a quiz** from arbitrary study material — paste notes and get a
  ready-to-edit quiz in Markwise's own format.
- 🗂️ **Structure messy vocabulary** — turn a sloppy bilingual list into a clean
  vocabulary set.

These are **opt-in cloud calls** using *your* key. Nothing leaves your device
unless you turn them on and trigger them. Everything generated lands in the same
**review → save** flow, so you always see and approve it before it's added.

## The five tabs at a glance

| Tab | What you do there |
|---|---|
| **Library** | Browse, import, and organize your quizzes & vocabulary sets |
| **Practice** | Start a Training or Exam session (or jump back into a recent one) |
| **Stats** | See your history and what's due for review |
| **Profile** | Your name, backup/restore, and the AI-features toggle + key |

*(Flashcard study and the import/AI generators are reached from the Library and
Practice flows.)*

---

# Part 2 — For Developers

> The authoritative coding conventions live in [`CLAUDE.md`](../CLAUDE.md) and
> [`.claude/rules/`](../.claude/rules/). This section is the map; those are the law.

## What it is, technically

A **local-first iOS 18+ app** built against the **iOS 26 SDK** (Liquid Glass),
in **Swift 6.1 / Swift 6 language mode** (strict concurrency). It's an SPM
**multi-package monorepo** under [`Packages/`](../Packages/). The Xcode project
([`Markwise.xcodeproj`](../Markwise.xcodeproj)) is a thin `@main` shell that just
presents `AppFeature.RootView`. A root `myquizzes` CLI exercises the pure core on
a plain macOS toolchain.

## Architecture in one breath

Strict, layered dependencies — **the direction is a hard rule.** A feature package
**never** depends on another feature; shared things go in a core package, and
cross-feature wiring happens only in `AppFeature`.

```
CoreModels  ── pure value types + repository/AI protocols + seeded RNG (Foundation only)
   ├─ MarkdownParser  .md ⇄ ParsedQuiz / vocab + diagnostics   (+ swift-markdown)
   ├─ QuizEngine      session state machine, scoring, shuffle  (seeded, deterministic)
   ├─ Statistics      aggregates [SessionRecord], due-for-review
   └─ VocabularyKit   Leitner scheduler + translation-quiz builder
Persistence  ── SwiftData ModelActors + file store, behind CoreModels' protocols
DesignSystem ── Liquid Glass components + tokens (the only place that knows glass)
AIExplanation ─ Claude-backed services (explain / generate quiz / structure vocab) + Keychain
Feature pkgs ── Library · Quiz · Results · Stats · Profile · Import · Vocabulary
AppFeature   ── composition root: root TabView + glue; injects concrete actors
Markwise.xcodeproj ── @main shell → AppFeature.RootView
```

### Package inventory

| Package | Layer | Purpose |
|---|---|---|
| `CoreModels` | core (pure) | Domain value types; `Sendable` `struct`s; repository **and** AI-service protocols; `SeededGenerator` |
| `MarkdownParser` | core (pure) | `.md` → `ParsedQuiz` / `VocabularySet` and back; collects `Diagnostic`s instead of throwing |
| `QuizEngine` | core (pure) | Session state machine, seeded selection/shuffle, all-or-nothing scoring |
| `Statistics` | core (pure) | Aggregates `SessionRecord`s; spaced-review signals |
| `VocabularyKit` | core (pure) | `LeitnerScheduler` + `VocabularyQuizBuilder` (deck/quiz derived from a set) |
| `Persistence` | infra | SwiftData `ModelActor`s + file store implementing the `CoreModels` protocols |
| `DesignSystem` | UI infra | Tokens (`Spacing`/`Radius`/`Typography`/`ColorTokens`/`Motion`) + Liquid Glass surfaces |
| `AIExplanation` | infra | Concrete Claude services for explanations, quiz generation, vocab structuring; `KeychainStore` |
| `LibraryFeature` | feature | Category/Topic/Folder tree; browse & manage content |
| `QuizFeature` | feature | The quiz runner: view model owns `QuizSession`, renders via DesignSystem |
| `ResultsFeature` | feature | Session summary + history views |
| `StatsFeature` | feature | Progress / due-for-review UI |
| `ProfileFeature` | feature | Name, backup/restore, AI toggle + API key entry |
| `ImportFeature` | feature | Import `.md`, AI-generate quiz/vocab, review-before-save pipeline |
| `VocabularyFeature` | feature | Flashcard deck + vocabulary study UI |
| `AppFeature` | root | Root `TabView`, onboarding, composition/injection of all concretes |

## Key design rules (don't break these)

1. **Layering is a hard rule** — features depend only on core packages +
   `DesignSystem`, never on each other.
2. **The pure core stays pure** — `CoreModels`/`MarkdownParser`/`QuizEngine`/
   `Statistics`/`VocabularyKit` import **only Foundation** (parser also
   swift-markdown). They build and `swift test` on any toolchain.
3. **Quiz/vocab logic lives in the engines, not the UI.** Views hold a `@State`
   view model, send intents, render results — no business logic.
4. **Persistence and AI are reached only through `CoreModels` protocols**
   (`SessionRepository`, `LibraryRepository`, `ProfileRepository`,
   `ExplanationService`, `QuizGenerationService`, `VocabularyGenerationService`).
   Concretes are injected at the `AppFeature` root; `InMemory*` doubles serve
   previews/tests.
5. **Concurrency:** domain types are `Sendable` value types; view models are
   `@MainActor @Observable final class`; repositories/services are `actor`s. No
   `@unchecked Sendable` to silence the compiler.
6. **UI uses DesignSystem tokens only** — no hard-coded numbers/colors; all glass
   goes through `glassSurface(_:)`; iOS 26 APIs gated with `#available`.
7. **AI is opt-in and offline-first** — every generator funnels through the
   parse → review → save pipeline; the app is fully usable with AI off.

## Build & test

> **Toolchain note (this machine):** the default Command Line Tools are corrupted,
> so run this once per shell before any `swift`/`xcodebuild`:
> ```bash
> export DEVELOPER_DIR=~/Downloads/Xcode.app/Contents/Developer
> ```

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
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Tests use **swift-testing** (`import Testing`, `@Suite`, `@Test`, `#expect`) — not
XCTest. The pure core carries the heaviest coverage; engine tests rely on the
seeded RNG for deterministic assertions.

## Where to add things

- New **screen / UI flow** → a feature package (compile-checked + testable in
  isolation), then wire it into `AppFeature`. Never into a sibling feature or the
  thin app target.
- New **domain type / shared abstraction** → `CoreModels` (keep it pure &
  `Sendable`, write an explicit `public init`).
- New **quiz/vocab behavior** → the relevant engine (`QuizEngine` /
  `VocabularyKit`), thread the seed for determinism.
- New **visual primitive** → a token in `DesignSystem/Tokens.swift`, not an inline
  literal.

---

## See also

- [Tutorial.md](Tutorial.md) — write your first quiz and run a session
- [../README.md](../README.md) — quick build/run reference
- [../CLAUDE.md](../CLAUDE.md) + [../.claude/rules/](../.claude/rules/) — full conventions
- [../Samples/AZ-900.md](../Samples/AZ-900.md) — a complete real quiz file
