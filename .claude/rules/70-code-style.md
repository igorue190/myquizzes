# Code Style

Match the surrounding code. The conventions below are consistent across the repo —
follow them in new files.

## File header block

Every source file opens with a header comment: the filename, the package name, and a
short paragraph explaining the file's *purpose and its place in the architecture* (not
just what, but why it lives where it does). Example:

```swift
//
//  QuizSessionViewModel.swift
//  QuizFeature
//
//  The one stateful object in the quiz runner. It owns a value-type `QuizSession`
//  from the engine, forwards user intents to it, and exposes display-ready state…
//
```

Keep these accurate when you move or repurpose a file.

## Sectioning & naming

- Use `// MARK: - Section` to divide files (Intents, Display state, Implementation,
  Fixtures, etc.). View models commonly group: init/factory, Intents, derived/display
  state, and domain→DesignSystem mapping.
- Document non-obvious types and properties with `///` doc comments — especially the
  *why* (e.g. why a property is `@ObservationIgnored`, why an id is zero-based).
- Token/constant namespaces are caseless `enum`s (`Spacing`, `Radius`, `Typography`).

## Public-API hygiene

- Mark the package's public surface `public` explicitly, and write an explicit
  `public init`. The implicit memberwise init is not `public`.
- Expose mutable view-model state as `public private(set) var`; mutate it only through
  intent methods.
- Keep internal helpers `private`/`internal`; don't widen access beyond what other
  packages actually consume.

## General

- Prefer value types and computed properties over stored mutable state (see
  `30-domain-models.md`).
- No hard-coded UI literals — use DesignSystem tokens (see `40-design-system.md`).
- Don't add a third-party dependency without a clear reason; the only external dep is
  `apple/swift-markdown`. The product is deliberately offline and backend-free.
