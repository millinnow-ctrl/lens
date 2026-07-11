# LensMood — rules for every session

Read `docs/MASTER_DIRECTIVE.md` before changing anything. It is the owner's
standing product standard and overrides ad-hoc instincts.

Hard rules:

- **Product code goes in `LensMoodApp/`** (pure SwiftUI + Core Image/Metal +
  Vision + AVFoundation; XcodeGen project; compiled by
  `.github/workflows/swiftui-ci.yml` on every push).
- **`lensmood-native/` is the frozen reference** (Expo SDK 54 + React Native
  0.81 + React Native Skia, TypeScript). Never add features there. Never
  delete/rename it before the parity gate passes. Permanent refs:
  `react-native-reference-complete`, `reference/react-native-complete`.
- **The looks are the product.** `reference/` renders the reference engine
  headless in Node (`render.cjs`, `lutbake.cjs`) to produce golden fixtures.
  A Swift stock is done only when it passes fixture comparison AND owner
  visual approval — never because it compiles.
- Label every visual change: parity correction / performance optimization /
  intentional camera refinement / bug fix / product redesign.
- Testing paths are documented in `docs/TESTING.md` (Expo Go runs the
  reference app incl. Skia; only the two custom Swift modules + RevenueCat
  need a dev build; paid Apple account is for TestFlight/EAS-device/IAP).
- Monetization gates are OFF for now (`EVERYTHING_FREE_FOR_NOW` in the
  reference store) — pricing is decided at the end.
- Report per §16 of the directive: implemented vs documented, tests run,
  output changes with side-by-sides, exact next step. Name frameworks
  precisely; never say "native" ambiguously.
