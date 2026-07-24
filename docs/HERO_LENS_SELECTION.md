# Hero-Lens Selection — first learned-refinement experiment (R60-8)

The mandate: pick **one** lens for the first Layer-3 (learned refinement) proof
of concept — not all 18. Score candidates on evidence, don't choose by taste,
and build only the winner. Deterministic quality must remain the fallback.

## Candidates & scores (1–5, higher is better; risk rows: higher = safer)

Baseline quality is the CI-measured regression MAE (lower MAE = closer to
reference; shown for context, not as an absolute quality verdict).

| Criterion (weight) | Polaroid | Film Noir | Pastel Cinema | GQ Editorial | A24 Still |
|---|---|---|---|---|---|
| Dataset availability (×2) | 5 | 4 | 3 | 3 | 3 |
| Deterministic baseline (MAE) | 4 (17.9) | 4 (≤20) | 4 (17.2) | 4 (18.6) | 3 (22.0) |
| Visual clarity of the target | 5 | 5 | 3 | 4 | 3 |
| User appeal (×2) | 5 | 4 | 3 | 3 | 3 |
| Commercial value (×2) | 5 | 4 | 3 | 4 | 3 |
| Expected AI improvement (×2) | 5 | 5 | 2 | 3 | 3 |
| Model complexity (simpler=5) | 4 | 4 | 4 | 3 | 4 |
| Device feasibility | 4 | 5 | 4 | 4 | 4 |
| Identity-preservation safety (×2) | 4 | 5 | 4 | 2 | 4 |
| Premium potential (×2) | 5 | 4 | 3 | 4 | 4 |
| **Weighted total** | **68** | **63** | **44** | **48** | **47** |

## Winner: **Polaroid** (runner-up: Film Noir)

**Why Polaroid.**
- **Dataset**: the largest, most licensable body of authentic references of any
  candidate (decades of real instant film), and the look is a *process*
  (chemical dye diffusion, uneven development, edge bleed, dreamy bloom) that is
  exactly what a small learned img2img residual captures better than hand-tuned
  Core Image — a clear, visible improvement over the deterministic pass.
- **Appeal & commercial**: instant film is the single most recognizable, most
  requested aesthetic in consumer photo apps → the obvious anchor for a premium
  "Instant / Signature" pack.
- **Safety**: the transform is tonal/chemical, not structural — low facial-
  identity risk — and we already ship a strong deterministic Polaroid
  (`polaroid` recipe, LUT + instant-frame composite) as the guaranteed fallback.

**Why Film Noir is the runner-up (and a strong second experiment).** Learned
*directional relighting* (synthesizing chiaroscuro) is the one place AI most
clearly beats deterministic tone-mapping, and it's the safest identity-wise
(pure luminance). It scores lower only on dataset breadth and commercial
pull versus Polaroid. If the Polaroid POC validates the pipeline, Noir is next.

**Rejected for first POC.** Pastel Cinema — deterministic already nails it, so
the expected AI delta is small. GQ Editorial — strobe/skin work carries the
highest identity-preservation risk (learned skin retouching can alter a face),
wrong place to start. A24 Still — weakest baseline and least obvious AI win.

## What actually gets built now vs. later

Per the agreed scope (Apple Vision now; scaffold Layer 3; no device to validate
a trained model this round):

- **Now (R60-8, in-repo, CI-verified):** the `RefinementService` /
  `InferenceCoordinator` abstraction + a `RefinementModelDescriptor` for the
  Polaroid hero model wired through the delivery/device-tier/fallback path — so
  the model is a drop-in. The lens still renders its deterministic look; the
  refinement stage is a no-op until a model is installed.
- **Deferred (needs a Mac training box + curated dataset + on-device
  validation):** the actual distilled Polaroid residual model. Documented as the
  next phase with a dataset spec, not shipped unproven.

This keeps the honest rule: **deterministic where possible, learned where
useful, nothing exposed until it beats the current app on a real device.**
