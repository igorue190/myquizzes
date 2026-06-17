# Swift 6 Strict Concurrency

The project builds under **Swift 6 language mode** (`.swiftLanguageMode(.v6)` on UI
targets; tools version 6.1 everywhere). Treat concurrency-safety as a compile
requirement, not an afterthought.

## Conventions

- **Domain & value types are `Sendable`.** Every model in `CoreModels` is declared
  `Sendable` (usually alongside `Equatable, Codable, Hashable, Identifiable`). Keep new
  value types `Sendable`; prefer `let` properties and value semantics.

- **The seeded RNG is `Sendable` for reproducibility.** `SeededGenerator` (SplitMix64)
  is a `Sendable` `RandomNumberGenerator`. Anything that needs randomness in the
  engine takes a seed and threads this generator so sessions are reproducible and
  unit-testable. Do not reach for `SystemRandomNumberGenerator` in engine code.

- **View models are `@MainActor @Observable final class`.** Mutating an observed
  stored property is what drives SwiftUI updates. Mark properties that should *not*
  trigger observation (callbacks, cached tasks, plain flags) with
  `@ObservationIgnored`. Expose mutable state as `public private(set)`.

- **Repositories are actors behind `Sendable` protocols.** The protocols
  (`SessionRepository`, etc.) live in `CoreModels` and are `Sendable` with `async`
  methods. Concrete types are `actor`s: SwiftData ones conform to `ModelActor` (with
  `nonisolated let modelContainer`/`modelExecutor`); the test doubles are plain
  `actor InMemory*Repository`.

- **Async timers/work use structured `Task`** captured weakly and cancelled
  explicitly. See the exam clock in `QuizSessionViewModel`: a `Task` stored in an
  `@ObservationIgnored` property, `[weak self]`, `Task.sleep`, guarded by
  `Task.isCancelled`, and cancelled on `submit`/deinit. Don't leak tasks.

- **Computed over stored for shared non-Sendable values.** E.g. `brandGradient` is a
  computed `static var`, not a stored one, so it stays concurrency-safe. Follow that
  pattern for SwiftUI types that aren't trivially `Sendable`.

If you hit a strict-concurrency error, fix the data-sharing model (isolation,
`Sendable`, value semantics) — do **not** silence it with `@unchecked Sendable` or
`nonisolated(unsafe)` unless there's a documented, reviewed reason.
