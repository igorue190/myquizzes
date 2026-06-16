# Markwise

A local-first iOS app that turns Markdown (`.md`) study files into interactive
quizzes (Training + Microsoft-exam-style Exam modes). No backend, no sign-in,
fully offline. See [Markwise-iOS-Technical-Plan.md](Markwise-iOS-Technical-Plan.md)
for the full product & architecture specification this repo implements.

---

## Status

Built up package-by-package from the technical plan. Everything below is
**compiled and verified** (pure packages via `swift test`; iOS packages and the
app via `xcodebuild` against the iOS 26.2 SDK), and the iOS app **builds,
installs, and launches in the simulator**.

| Package | What it is | Verified |
|---|---|---|
| `CoreModels` | Domain value types + seeded RNG (§7) | ✅ 7 tests |
| `MarkdownParser` | `.md` → `ParsedQuiz` + diagnostics, AST-based via `apple/swift-markdown` (§5) | ✅ 12 tests |
| `QuizEngine` | Session state machine, seeded selection/shuffle, all-or-nothing scoring (§8) | ✅ 12 tests |
| `myquizzes` (root exe) | CLI demo: parse a quiz → run a session → print a score report | ✅ runs |
| `DesignSystem` | Liquid Glass components, tokens, theme (§9) | ✅ iOS build |
| `QuizFeature` | `@Observable` view model + runner/result views wiring engine → DesignSystem | ✅ iOS build |
| `AppFeature` | Root `TabView` (Library · Practice · Stats · Profile); Practice wired end-to-end | ✅ iOS build |
| `Markwise.xcodeproj` | `@main` app target | ✅ builds + launches in simulator |

### Not built yet (next phases, per the plan)
`Persistence` (SwiftData + file store), `LibraryFeature` (category/topic/folder
tree + import), `ResultsFeature`/`Statistics`, and the Profile feature. The
Library/Stats/Profile tabs are guided empty states for now; the exam timer
auto-submit and the question-palette grid are also still to come.

---

## Layout

```
myquizzes/
├── Markwise.xcodeproj         # the iOS app target (@main → AppFeature.RootView)
├── App/MarkwiseApp.swift       # @main entry (thin shell)
├── Package.swift               # the `myquizzes` CLI demo
├── Sources/main.swift          # demo entry point
├── Samples/AZ-900.md           # example quiz in the documented Markdown format
└── Packages/
    ├── CoreModels/             # domain value types (no dependencies)
    ├── MarkdownParser/         # CoreModels + swift-markdown
    ├── QuizEngine/             # CoreModels
    ├── DesignSystem/           # Liquid Glass (iOS 18+, iOS 26 APIs gated)
    ├── QuizFeature/            # CoreModels + QuizEngine + MarkdownParser + DesignSystem
    └── AppFeature/             # CoreModels + DesignSystem + QuizFeature
```

This mirrors the plan's module map (§6.3): each feature depends only on the core
packages + DesignSystem, never on another feature.

---

## Building

> **Toolchain note.** This machine's Command Line Tools are corrupted, so builds
> use the Xcode toolchain explicitly. Run this once per shell:
> ```bash
> export DEVELOPER_DIR=~/Downloads/Xcode.app/Contents/Developer
> ```
> (Or `sudo xcode-select -s ~/Downloads/Xcode.app/Contents/Developer` to make it
> the default. Moving Xcode into `/Applications` is optional.)

**Pure core — tests:**
```bash
swift test --package-path Packages/CoreModels
swift test --package-path Packages/MarkdownParser
swift test --package-path Packages/QuizEngine
```

**CLI demo:**
```bash
swift run myquizzes                 # bundled Samples/AZ-900.md
swift run myquizzes path/to/quiz.md # your own file
```

**iOS app (simulator):**
```bash
xcodebuild -project Markwise.xcodeproj -scheme Markwise \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

# install + launch on a booted simulator
UDID=$(xcrun simctl list devices available | grep -m1 'iPhone' | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot "$UDID"; xcrun simctl bootstatus "$UDID"
APP=$(xcodebuild -project Markwise.xcodeproj -scheme Markwise -showBuildSettings 2>/dev/null | awk '/ TARGET_BUILD_DIR /{d=$3}/ FULL_PRODUCT_NAME /{p=$3}END{print d"/"p}')
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" com.markwise.app
```

A `MARKWISE_UITEST_SCREEN` env var (`practice` / `runner`) deep-links the app to
a screen — handy for snapshot tests:
`SIMCTL_CHILD_MARKWISE_UITEST_SCREEN=runner xcrun simctl launch "$UDID" com.markwise.app`.

---

## The Markdown quiz format (summary)

A question is a `##`/`###` heading (the prompt), a task-list of answers
(`- [x]` correct, `- [ ]` wrong), and an optional explanation blockquote.
Optional `<!-- type: single|multiple|truefalse -->` and `<!-- tags: a, b -->`
comments refine it; optional YAML front matter sets file-level metadata. See
[Samples/AZ-900.md](Samples/AZ-900.md) for a complete example and §5 of the plan
for the full spec.

```markdown
## Which cloud service model gives the most control over the OS?
<!-- type: single -->

- [ ] SaaS
- [ ] PaaS
- [x] IaaS

> **Explanation:** IaaS exposes the VM and OS to the customer.
> **Reference:** https://learn.microsoft.com/azure/
```
