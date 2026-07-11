# `@/store` — app-state layer API

Durable app state (plan, credits, history, favorites, presets, account,
streak) persisted to AsyncStorage under `lensmood.v1`, plus the haptics
wrapper. Ported from the web app's `src/lib/store.tsx` business rules.
Session-only state (current photo/roll/video, active style, live slider
params) is **not** here — keep it in your screen; the store only holds what
must survive a relaunch.

## Setup

Wrap the app once, inside the root layout:

```tsx
import { AppProvider } from '@/store'

<AppProvider>{/* Stack */}</AppProvider>
```

Then anywhere below it:

```tsx
import { useApp, haptics, FREE_CREDITS } from '@/store'
```

## `useApp(): AppState`

Throws outside `<AppProvider>`. Fields:

### Hydration

- `ready: boolean` — false until the AsyncStorage slice has loaded.
  Gate plan/credit-dependent UI (or hold the splash) on it; before `ready`
  the state is the pristine free-plan defaults.

### Plan and gating

- `plan: 'free' | 'creator' | 'pro' | 'studio'`
- `setPlan(p: Plan)` — call after a verified purchase/restore (RevenueCat
  team) or from the demo pricing flow.
- `isPaid: boolean` — plan !== 'free'. **Watermark rule:** free exports get
  the watermark, so pass `watermark: !isPaid` to the engine/export flow.
- `hasVideoPlan: boolean` — pro or studio. **Video develops are Pro+.**

### Credits (free plan: 5/month)

- `FREE_CREDITS = 5` (exported const)
- `creditsLeft: number` — `Infinity` on paid plans; `0..5` on free. Resets by
  local month key automatically (on launch and across an in-app month
  rollover).
- `firstDevelopFree: boolean` — true until anything has ever been developed;
  the first develop never costs a credit (the aha moment). Use for the
  "your first roll is on the house" copy.
- `spendCredit(): boolean` — call once right before a develop. Returns `true`
  when allowed (paid plan, first-ever develop, or a credit was decremented);
  `false` means out of credits — show the paywall and do not develop.

### History (developed shots, capped at 60)

- `history: HistoryEntry[]` — newest first.
  `HistoryEntry = { id, thumb, styleId, styleName, date }`; `thumb` is the
  engine's developed `file://` JPEG URI (`DevelopResult.uri`); `date` is
  `Date.now()` ms.
- `addHistory({ thumb, styleId, styleName })` — id/date filled in; also
  updates `tried` and the day `streak` as a side effect.
- `removeHistory(id: string)`
- `HISTORY_CAP = 60` (exported const)

### Favorites

- `favorites: string[]` — style ids.
- `toggleFavorite(styleId: string)`

### Saved presets (capped at 20)

- `presets: SavedPreset[]` — `{ id, name, styleId, params: StyleParams }`.
- `savePreset(name, styleId, params): SavedPreset | null` — params are
  clamped to finite 0..100 per slider against the style's defaults; returns
  `null` when `styleId` is unknown.
- `applyPreset(id): SavedPreset | null` — returns a fresh clone of the
  stored preset (feed `styleId` + `params` to your develop screen).
- `removePreset(id: string)`
- `PRESET_CAP = 20` (exported const)

### Account

- `user: { name: string; email: string } | null`
- `signIn(user)` / `signOut()` — signOut also drops the plan back to `'free'`.

### Streak and collection

- `streak: { count: number; last: string }` — consecutive-day develop streak,
  `last` is `'YYYY-MM-DD'` (empty string when never developed). Maintained by
  `addHistory`.
- `tried: string[]` — every style id ever developed (collection meter).

## Standalone helpers (also exported from `@/store`)

- `sanitize(raw: unknown, fallback: Persisted): Persisted` — field-by-field
  validation of anything loaded from disk; malformed fields fall back
  individually. History thumbs must start with `file://` or `data:image/`;
  presets with unknown style ids are dropped and params clamped 0..100.
- `clampParams(styleId: string, raw: unknown): StyleParams | null` — the
  0..100 clamping contract on its own; use it for deep-link param decoding.
- `freshPersisted(): Persisted` — the pristine default slice.
- Types: `AppState`, `Persisted`, `Plan`, `HistoryEntry`, `SavedPreset`,
  `User`, `Streak`.

## `haptics` (`@/store` or `@/store/haptics`)

All methods are synchronous fire-and-forget, safe no-ops when haptics are
unavailable (simulator/web):

- `haptics.light()` — slider detents, card taps, filmstrip swipes
- `haptics.medium()` — develop kicked off, preset applied, favorite on
- `haptics.heavy()` — export saved, purchase completed
- `haptics.selection()` — segmented control / style chip tick
- `haptics.success()` / `haptics.warning()` — notification-grade feedback
  (develop finished / out of credits)

## Persistence notes

- Single JSON blob at AsyncStorage key `lensmood.v1`; writes happen on every
  state change after hydration, with a trimmed-history retry if storage is
  full. Do not write to `lensmood.*` keys from other modules.
- History thumbs live in the app cache directory; the OS may purge them.
  Render with a graceful `onError` fallback.
