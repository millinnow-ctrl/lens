# LensMood — rules for Codex and coding agents

Read `docs/MASTER_DIRECTIVE.md` completely before changing anything. It is the
owner's standing product and engineering standard.

## Repository boundaries

- Permanent product work belongs in `LensMoodApp/`: SwiftUI, Core Image,
  Vision, AVFoundation, and small custom kernels only when justified.
- `lensmood-native/` is the frozen React Native/Expo/Skia reference. Do not add
  product features there. Change it only when a critical reference-build or
  fixture-generation repair is required.
- `reference/` is the parity harness and visual ground truth. Never update a
  fixture merely to make a failing implementation pass.

## Required gates

- Port before refining. Label each visual change as a parity correction,
  performance optimization, intentional camera refinement, bug fix, or product
  redesign.
- A camera is complete only after deterministic rendering, numeric comparison,
  a side-by-side review artifact, and owner visual approval.
- Keep rendering stages explicit, deterministic, testable, and independently
  disableable.
- Do not claim that metadata, architecture, copied assets, placeholders, or a
  successful compile are finished product features.
- Keep monetization disabled during development.
- Do not use unverified simulation claims or third-party brand names in new
  public-facing copy. Prefer “camera personality” and “scene-aware development.”
- UI copy must never expose implementation status, phase names, AI labels,
  model names, debug language, or placeholder promises.

## Reporting

For every meaningful pass report what changed, why, files touched, tests run,
what passed, what remains unverified, whether rendering output changed, risks,
tradeoffs, and the exact next step. Name SwiftUI, UIKit, Core Image, Metal,
Vision, AVFoundation, React Native, Skia, and Expo precisely.
