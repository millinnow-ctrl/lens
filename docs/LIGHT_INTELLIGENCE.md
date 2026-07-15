# Light Intelligence (R61+) — the light is read, not painted

Owner directive: each lens must behave like a **camera with physics**, not a
color overlay. Flash looks must understand reflectivity and surfaces; light-
driven looks must respond to actual sources; noir must respect direction;
video noise must follow gain. This doc records the shipped passes, the
evidence loop that produces them, and the backlog for the next rounds.

## The iteration loop (repeat every round)

1. **Critique panel** — independent agents (an authenticity critic and a
   light-physics critic with pixel measurements) audit renders across ≥3
   scenes (daylight portrait, night sources, real-flash party). Output:
   ranked offenders + measured failures.
2. **Prototype tournament** — 2–3 algorithm variants per target implemented
   as throwaway local prototypes on real photos (scratchpad only; owner
   photos never enter the repo). Rank visually + by judge agent.
3. **Port winners to Swift** (`FilmEngine+LightIntelligence.swift`) —
   recipe-gated so untouched stocks stay byte-identical; unit tests pin the
   physics (including refusal rules); parity ceilings handled honestly
   (provisional bump with label → tighten to CI-measured + 2).
4. **CI verify + visual review** — green build, then personally inspect the
   parity side-by-sides; iterate offenders.

Constraints: signals must exist on-device (`SceneAnalyzer` meter: key,
percentiles, illum, `lights[]` with per-source position/intensity/true color;
Vision person mask + faces). Passes must be deterministic. The frozen
reference is never modified.

## Shipped passes (R61)

| Pass | Stocks | Physics | Measured failure it fixes |
|---|---|---|---|
| `applyFlashPhysics` | iphone-flash 1.0 · photobooth .75 · y2k .65 · point-shoot .5 · disposable .45 | Scene-relative specular map (bright+desaturated = glass/screens/metal/eyes) + subject-anchored falloff; background falls toward ambient, **never lifts**; strength ∝ scene darkness | iphone-flash lifted backgrounds ×4.6, reversing real flash falloff; zero specular response on phone screens/glasses |
| `applySourceBloom` | tokyo-neon 1.0 | One tinted glow per detected source **in the source's own hue**; unlit areas sink; **refusal rule**: no emissive sources → plain bloom (colored = tint sat > 0.18, or any hot source when key < 0.30) | Neon washed a sunless plaza magenta; colored *unlit* facades (sat 0.11→0.67) |
| `applyKeyShadow` | film-noir 0.7 | Shadows deepen with distance from the meter's key light; highlights hold; largest face partially preserved; honest no-op with no key | Noir had zero directionality (face L/R ratio 0.952→0.948 — a global curve) |
| `gainGrainFactor` | security-cam, camcorder-90s | Grain ∝ scene darkness (≈1.7× night, 0.4× daylight) — real AGC | Noise identical in night vs day (σ 9.9 vs 8.4) |

Decision notes surface only when a pass actually engaged ("Glow followed the
light sources", "Key light held to one side", "Gain noise rose with the dark").

## Verified so far

- Engine compiled; determinism holds for all four new-pass stocks.
- Refusal rule byte-identical to plain bloom on non-emissive scenes (unit).
- Parity: film-noir and tokyo-neon goldens stayed under the provisional
  ceilings (32 / 34) — tighten to measured+2 once read from a green run.
- Prototype sheets (owner-reviewed): source-hued night bloom, flash plunge on
  the party scene, directional noir on the daylight portrait.

## Backlog (R62+ candidates, from the critique panel)

1. **Edge-band artifact (engine-wide)** — smeared top/left frame edges seen in
   several reference renders (grain/warp edge clamp). Verify whether the Swift
   geometry warp shares it; fix once, engine-wide.
2. **Super-8 night reciprocity** — ISO-40 film can't see at night: pull
   exposure with a shadow-crushing toe when key is low (grain stays fixed —
   emulsion, not gain).
3. **Eye catchlights** — SegmentationService already extracts eye landmark
   centroids; composite small catchlights scaled by scene darkness for the
   flash family.
4. **Y2K CCD clip** — harsh highlight clipping + vertical smear on hot
   sources (CCD blooming), replacing the current milky lift.
5. **Camcorder comet-tails** — vertical smear on clipped highlights at night.
6. **Photobooth curtain** — beyond-arm's-length falls to near-black after the
   B&W conversion (the booth is the most constrained lighting rig there is).
7. **Timestamp honesty** — camcorder/security overlays should not claim
   "AM 4:40" on a daylight frame; drive plausible hour from scene key.
8. **Shared-sticker dedup** — camcorder and security-cam use one overlay
   asset/font; differentiate so back-to-back use doesn't expose the template.
