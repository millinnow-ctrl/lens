# iOS Citizenship — Share Sheet, Widgets, Lock Screen

Roadmap item 4 of `docs/MASTER_PROMPT.md` §VII. Everything here is pure
SwiftUI + WidgetKit + UIKit (extension shells) + Core Image (the engine),
compiled from the same XcodeGen spec (`LensMoodApp/project.yml`) and embedded
in the app bundle. Nothing requires signing beyond an unsigned simulator
build: **no App Groups, no push, no capabilities, no team.**

## What shipped

### 1. Share-Sheet extension — target `LensMoodShare`

Share any image from any app → "LensMood" appears in the share sheet → a
compact develop surface: the photograph in a viewfinder well, the full
18-camera film rail (gradient swatch chips from `Stock` metadata), one
intensity slider, Save to Photos, Cancel.

- **Sources**: `LensMoodApp/ShareExtension/ShareViewController.swift` (UIKit
  principal class hosting SwiftUI) and `ShareDevelopView.swift` (the whole
  visible surface). Shared product files are compiled directly into the
  extension target (listed explicitly in `project.yml`): `Sources/Engine/`
  (complete render engine incl. scene meter and LUT loading),
  `Sources/Model/Stock.swift`, `Sources/Model/StyleDefinition.swift`,
  `Sources/Theme.swift`, `Sources/Services/VisionService.swift`,
  `Sources/Services/PhotoLibraryWriter.swift`, plus the `Resources/luts`
  folder (the LUT stocks' color cores).
- **Memory budget (honest)**: share extensions live under a ~120 MB ceiling.
  The incoming image is decoded once and re-rendered to a **1500 px working
  frame** (orientation normalized); previews develop at **1024 px**; the
  save develops the 1500 px frame. The subject pass is off
  (`analyzeSubjects: false`): the scene meter still reads every photograph —
  adaptive exposure, flash speculars, source bloom, key shadow, gain-driven
  grain, night reciprocity all behave — but **face protection and
  flash-falloff subject masking do not run in the extension** (Vision face +
  person-mask inference is the least predictable memory consumer). The full
  app remains the quality path; the extension is the convenience path, and
  its output says so nowhere — it is a real engine develop, just capped at
  1500 px.
- **Activation rule**: `NSExtensionActivationSupportsImageWithMaxCount: 1`
  (never `TRUEPREDICATE`, which App Review rejects).
- The grain seed uses the same per-camera formula as the app's Develop flow,
  so the same photo + camera + 100% intensity develops identically (modulo
  the 1500 px cap and the disabled subject pass, both stated above).

### 2. Home-Screen widgets — target `LensMoodWidgets` (WidgetKit)

"Camera of the Day": a deterministic rotation through all 18 cameras —
`CameraOfTheDay.index(on:)` = day-of-year % 18 — so the widget needs no
storage, no network, and no shared state. Small and medium families, drawn in
the app identity (white surface card, the camera's gradient swatch, name,
tagline, `bestFor`, EXIF strip on medium). Tapping deep-links to
`lensmood://develop/<stockID>`.

- Timeline: one entry now + one per midnight for a week, `.atEnd` reload.
- iOS 16/17 both handled: `containerBackground(for: .widget)` on 17 via an
  availability shim, self-padding on 16.

### 3. Lock Screen / StandBy accessories (iOS 16 WidgetKit families)

`accessoryCircular` (the aperture glyph on `AccessoryWidgetBackground`) and
`accessoryRectangular` (aperture glyph + LENSMOOD wordmark + today's camera
name). Same provider, same deep link. StandBy on iPhone shows widgets from
these accessory/system families automatically — no extra target needed.

### 4. Deep links in the app

- `lensmood` URL scheme registered via `CFBundleURLTypes` (XcodeGen `info:`
  block on the app target — this is the one Info.plist key that cannot be an
  `INFOPLIST_KEY_` build setting; `GENERATE_INFOPLIST_FILE` stays on and
  Xcode merges the two).
- `Sources/Model/DeepLink.swift` — strict pure parser (unknown routes and
  unknown camera IDs return nil). `RootView.onOpenURL` →
  `AppModel.open(url:)` → sets `pendingStock` (the existing "Shoot this film
  again" hand-off) and lands on the Cameras tab; HomeView pushes the develop
  view.

### 5. Tests (in the existing `LensMoodTests` target)

`Tests/CitizenshipTests.swift`: camera-of-the-day modulo pins + 18-day full
coverage + within-day determinism (fixed UTC calendar), deep-link round-trip
for all 18 cameras, malformed/foreign URL rejection, AppModel routing, and a
copy-hygiene sweep over `ShareExtension/` and `Widgets/` (which live outside
the `Sources/` sweep in FilmEngineTests).

## What deliberately does NOT need the paid Apple account

The widget design is metadata-only **on purpose**: it renders camera identity
(gradients, names, taglines) from compiled-in `Stock` data, so it needs no
App Group to reach the app's library and therefore no entitlements at all.
Everything above runs on a free team / unsigned simulator / CI exactly as the
app does today.

## What waits for the paid account (deferred, documented, not started)

- **Photo-showing widgets** ("latest develop", "this month's roll"): the
  widget process cannot read the app's sandbox, so these need an App Groups
  entitlement and a shared container the app writes thumbnails into.
  Entitlements mean provisioning; that is owner-account territory
  (`docs/TESTFLIGHT.md`). The `LibraryStore` write path would gain a
  "mirror a small JPEG + stock ID into the group container" step — nothing
  else changes.
- TestFlight distribution of the extensions (they ride the app's build; no
  extra work beyond signing).

## Testing steps

CI (`.github/workflows/swiftui-ci.yml`) builds all of this on every push —
the extensions are dependencies of the app target, so the existing
`-scheme LensMood` build compiles them, and the new logic tests run in the
existing test action. Manual, in Xcode on a simulator:

1. `cd LensMoodApp && xcodegen` → open `LensMood.xcodeproj`, run **LensMood**.
2. **Deep link**: `xcrun simctl openurl booted "lensmood://develop/tokyo-neon"`
   → app opens on Cameras and pushes Neon Night's develop view.
3. **Widgets**: long-press the Home Screen → add "Camera of the Day"
   (small/medium). Tap it → the day's camera opens in develop. Date-travel
   (Settings → General → Date & Time in the simulator) advances the rotation.
4. **Lock Screen**: on an iOS 16+ simulator, customize the Lock Screen → add
   the LensMood circular/rectangular accessories.
5. **Share sheet**: open Photos → share any image → LensMood → pick a camera,
   drag intensity, Save to Photos → the developed frame lands in the library
   app-free. First save asks for add-only Photos permission.
6. Run the unit tests: product scheme **LensMood** → Test (the new
   `CitizenshipTests` run with the suite).
