# DesignSystem: Tokens, Liquid Glass, Accessibility

All UI primitives live in the `DesignSystem` package. Feature views compose its
components; they do not invent their own visual language.

## Tokens are the single source of truth

Reference tokens from `Tokens.swift` — **never hard-code numbers or colors** in a view:

- **`Spacing`** (4pt grid: `xxs`…`xxxl`) for padding, stack spacing, gaps.
- **`Radius`** for corner radii. Nest a smaller radius inside a larger one so glass
  shapes stay visually concentric (HIG guidance).
- **`Typography`** — semantic faces built on Dynamic Type text styles (rounded design,
  monospaced for timers). Use these so the app scales with the user's text-size setting.
- **`ColorTokens`** — semantic, light/dark-adaptive brand/state/surface colors. Use
  state colors (`success`/`warning`/`danger`/`info`) **only when they carry meaning**.
  Build adaptive colors with `Color(light:dark:)` / `Color(hex:)`.
- **`Motion`** — standard animation curves; prefer these over ad-hoc `.easeInOut`.

If you need a value that isn't a token yet, add it to `Tokens.swift` rather than
inlining a literal.

## Liquid Glass goes through one door

`Glass.swift` is the **only** file that knows about iOS 26 Liquid Glass. Every surface
uses the `glassSurface(_:)` / `glassCapsule(_:)` view modifiers and a semantic
`GlassRole` (`.regular`, `.clear`, `.prominent`, `.tinted`) — describe surfaces by
*meaning*, not raw glass parameters. Apply `glassSurface` **last** in the modifier
chain (after padding). Use the provided button styles (`.glassPrimary`,
`.glassSecondary`) for CTAs.

Do not call `.glassEffect()` or system materials directly in feature code — route it
through `Glass.swift` so the three concerns below stay centralized.

## Accessibility is handled centrally — keep it that way

`GlassSurfaceModifier` already resolves, in priority order:
1. **Reduce Transparency** → opaque, fully legible fills (no translucency).
2. **iOS 26** → real `.glassEffect()`.
3. **iOS 18–25** → `Material` fallback (the iOS 26 APIs compile under the SDK but only
   run on 26+, so they're gated with `#available(iOS 26.0, *)`).

**Reduce Motion** disables interactive glass bounce and animation. When you add new
animated/interactive UI, honor `@Environment(\.accessibilityReduceMotion)` at the call
site (gate the `.animation(...)`), the way the button styles do. Gate any iOS 26-only
API with `#available` and provide a fallback.
