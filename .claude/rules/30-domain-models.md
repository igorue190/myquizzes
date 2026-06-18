# Domain Models & The Repository Boundary

Domain types live in `CoreModels` and are the shared vocabulary of the whole app.

## Value-type conventions

- **Domain entities are `struct`s, not classes.** They're transient value types
  produced by the parser and consumed by the engine — not ORM rows.
- **Standard conformance set:** `Sendable, Equatable, Codable, Hashable` — add
  `Identifiable` for anything rendered in a SwiftUI list. Look at `Choice`, `Question`,
  `ParsedQuiz`, `SessionRecord` for the canonical shape.
- **`id` is a deterministic zero-based `Int` index** within its parent (a `Choice`'s
  id is its index in the question; a `Question`'s id is its index in the quiz). This
  keeps parsed output fully deterministic. `SessionRecord` is the exception — it's a
  persisted record keyed by `UUID`.
- **Memberwise `public init` written explicitly**, with sensible defaults for optional
  fields (`explanation: String? = nil`, `tags: [String] = []`). Don't rely on the
  implicit memberwise init for `public` types — it isn't `public`.
- **Derived facts are computed properties**, not stored (`correctChoiceIDs`,
  `isMultipleAnswer`, `usableQuestions`, `percentage`). Keep stored state minimal and
  canonical.
- **Enums carry a `String` raw value when they map to the Markdown spec**, and the raw
  value matches the spec exactly even when the case name differs
  (`case trueFalse = "truefalse"`). Mark them `CaseIterable` when the UI enumerates them.

## Diagnostics, not exceptions, for bad input

Parsing keeps malformed questions in the result and reports problems as
`Diagnostic`s with a `severity`. `ParsedQuiz.usableQuestions` filters out
error-level questions so the engine only scores valid ones, while the UI can still
surface the broken ones. Prefer this "collect diagnostics, degrade gracefully"
approach over throwing on imperfect user files.

## Repository boundary

- Persistence protocols are declared **here in `CoreModels`** (`SessionRepository`,
  `LibraryRepository`, `ProfileRepository`): `Sendable`, `async throws` methods.
- Every protocol ships with an **`InMemory*` actor** in `CoreModels` for previews and
  tests, and a **SwiftData `ModelActor`** implementation in `Persistence`.
- SwiftData implementations encode the domain value type to JSON in an `@Model` entity
  (payload column) and decode on read, rather than mirroring every field as a stored
  property — see `SwiftDataSessionRepository`. Keep the domain model the source of
  truth; the entity is just storage.
