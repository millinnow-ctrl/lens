# LensMood Master Product and Engine Refinement Directive

Issued by the owner. This is the standing product standard — it supersedes
vague instructions ("make it more native," "improve the filters," "make it
feel premium"). Every future development pass is audited against it.

## 1. Core product definition

LensMood is not a standard filter app. Its central idea:

> A camera personality studies the photograph and then develops it according
> to its own photographic instincts.

The engine reads the photograph first (subject location, faces, scene
brightness, face-vs-background exposure, highlight placement, shadow depth,
light-source location, white-balance cast, saturation, local contrast, dynamic
range, mixed lighting, indoor/outdoor/night/flash/backlight/high-key
conditions) and each camera makes different decisions from that evidence.
The differentiation is not "18 presets" — it is 18 distinct ways of
interpreting the same scene. Do not weaken this during the SwiftUI rewrite.

## 2. Repository and migration rules

- `lensmood-native/` is the complete React Native reference application. It
  stays fully committed, recoverable (branches
  `react-native-reference-complete`, `reference/react-native-complete`),
  frozen as the functional/visual reference, available for fixture
  generation, and untouched except critical reference-build fixes. Do not
  delete/archive/rename/reorganize it until the SwiftUI parity gate passes.
- All permanent product work goes into `LensMoodApp/`. Never both.
- Parity before creative divergence. Per stock: reference render → committed
  golden fixtures → Swift render → numeric + perceptual comparison →
  side-by-side review grid → owner approval. Only then may a camera be
  intentionally refined. A refinement must never be disguised as a porting
  difference; label changes as parity correction / performance optimization /
  intentional camera refinement / bug fix / product redesign.

## 3. Engine architecture

- Core Image is the backbone: CIColorCube for the 10 LUT-sufficient stocks,
  parameterized Core Image graphs for the 8 adaptive stocks, Vision for
  subject understanding, AVFoundation + Core Image for video export.
- Small custom kernels only where necessary (deterministic grain, chroma
  bleed, selective halation, anisotropic flare, subject-mask relighting,
  optical edge effects, temporal tape artifacts). No bespoke Metal renderer
  unless profiling proves it necessary.
- The pipeline is explicit stages (decode/normalize → analyze → working color
  space → camera exposure/WB → tonal response → color response → skin →
  local subject/background → optics → halation → grain → artifacts →
  frame/timestamp → preview → export), each individually testable and
  disableable.
- Use a deliberate working color space. Evaluate and document linear-light vs
  gamma ops, extended linear sRGB / Display P3, HDR normalization, wide-gamut
  behavior, clipping strategy, export profiles. Avoid crushed wide-gamut
  color, inconsistent iPhone HDR, washed exports, preview/export mismatch,
  early 8-bit clipping.

## 4. Scene Analysis V2

Typed SceneProfile with global exposure (geometric mean, median, 1st/99th
percentiles, clipping fractions, dynamic range, high/low-key confidence),
color/lighting (illuminant, cast direction, mixed-light confidence,
warm/cool distribution, dominant hues, saturation, muted confidence, neon
confidence), subject understanding (face count/boxes/confidence, primary
face, person mask, saliency, subject/background luminance and contrast,
subject scale, group-shot confidence, no-subject confidence), image character
(local contrast, edge density, sharpness, motion blur, noise, flat-light /
backlight / sky / foliage / skin / indoor-outdoor / night confidences).
Never pretend uncertain classifications are certain — store confidences,
fall back gracefully.

## 5. Subject and skin handling

Apple Vision (`VNDetectFaceRectanglesRequest`,
`VNGeneratePersonSegmentationRequest`, saliency where useful) is the normal
production path; the skin flood-fill heuristic is fallback only. Skin
handling separates exposure protection, hue protection, texture protection,
smoothing, glow, local contrast, saturation, flash response — decided per
camera, never a universal beauty pass (Leica preserves texture; GQ polishes
with structure; Disposable allows uneven flash; Y2K sharpens and clips;
Noir preserves geometry and tonal separation; Tintype reinterprets tonally).
Test across diverse skin tones, ages, lighting, and groups.

## 6. Camera behavioral manifestos

Every camera gets a written behavioral specification (protects / sacrifices /
exaggerates / exposure / skin / shadow / highlight / color / night / flash /
grain / optics / failure character / where it excels / where it is
intentionally imperfect). The 18 identities are specified in the owner
directive of 2026-07-11 (Disposable, iPhone Flash, 90s Camcorder, Leica
Street, GQ Editorial, A24 Still, Film Noir, Y2K Digicam, Polaroid, Super 8,
Lomo, Kodachrome, Security Cam, Point & Shoot, Pastel Cinema, Tokyo Neon,
Photobooth, Tintype) — the full identity text lives with this directive in
the project history and is the acceptance standard for Phase C.

## 7. Camera differentiation testing

Formal test: for each source photo render all 18, produce labeled and blind
grids, measure pairwise perceptual similarity, flag too-close pairs, review
whether differences are behavior or mere tint. Test suite spans skin tones,
group shots, low light, nightclub flash, concert, neon, daylight, backlit,
cloudy, snow, beach, sunset, tungsten, LED, foliage, sky, pet, architecture,
no-human, HDR, underexposed, blurry, noisy, wide-gamut, HDR iPhone images.
A camera is not complete because one hero image looks good.

## 8. Develop experience

Develop feels like a darkroom and a camera brain: 2–4 concise, camera-specific
decision notes from real analysis ("Face protected", "Backlight recovered",
"Warm cast retained"), optional expanded view. Keep Original / Developed /
Compare; improve boundary haptics, alignment (no Polaroid frame mismatch),
press-and-hold original, consistent zoom/pan, preview-resolution indication.
Sliders are meaningful photographic controls, camera-aware labels, no
duplicate generic controls; advanced controls may vary per camera.

## 9. Home and camera selection

Choosing an instrument, not browsing e-commerce: personality, best use case,
visual character per card; consider one-photo-across-all-cameras preview;
concise personality lines, tactile selection, restrained haptics,
camera-specific micro-motion. Three coordinated modes: Home/Develop =
precision instrument; Print Room = warm physical magic; Camcorder =
immersive nostalgia.

## 10. Print Room refinement

Preserve shutter flash, motor sound, eject clip, delayed development,
settling motion, surface selection, photographed-object export. Improve
physical credibility: seeded deterministic position/rotation variation,
surface-specific shadow direction, paper thickness, subtle curl, background-
consistent light falloff, surface-dependent reflected color, realistic
contact shadow, slight perspective/lens behavior, high-res edges, face crop
protection, optional minimal handling artifacts. No default dust/scratch
damage. Result = an iPhone photograph of a real instant print.

## 11. Camcorder refinement

Live preview and exported file must match: explicit parity tests for grade,
chroma bleed, vignette, moving grain, scanlines, exposure breathing, dropout
behavior, timestamp, REC, timecode, orientation, frame rate, audio sync, HDR
source, portrait/landscape. A static LUT is insufficient for temporal
effects — the exporter reproduces time-dependent artifacts. One look, no
dials: the user chooses a camcorder, not an effect.

## 12. Performance and reliability

Profile on real iPhones (recent Pro, recent standard, older supported):
cold launch, decode, analysis, preview develop, slider response, memory
peak, full-res export, video export, thermal, cancellation, repeated-use
growth. Cancellation stops superseded renders; preview stays responsive;
export never blocks UI; orientation correct; panoramas handled; temp files
cleaned; preview and export differ only by resolution.

## 13. Testing and quality gates

Unit (scene meter, LUT loading, interpolation, deterministic grain, exposure
decisions, WB clamping, face selection, recipe decoding); golden-image
(fixed input/recipe/profile, deterministic output, mean + percentile +
perceptual error); behavioral (backlit protection triggers, no invented
faces, Tokyo Neon keeps neon, Noir is monochrome, Disposable ≠ iPhone Flash,
Polaroid compare aligns, gating consumes credits correctly); device tests
(permissions, share sheet, memory pressure, backgrounding, interruption,
orientation, AV sync, StoreKit, export cancellation).

## 14. Product language and marketing

No measured-simulation claims unless based on measured data. Use: "inspired
by iconic camera and film aesthetics", "scene-aware development", "camera
personalities", "developed for the light and subject in your photograph".
Review third-party brand names before launch; create neutral replacement
candidates preserving internal IDs and approved looks.

## 15. Execution order

Phase A safety (reference refs verified, golden fixtures, current output
documented, Swift CI stable, broader reference dataset) → Phase B parity
engine (Class A LUTs, Class B adaptive, scene meter, Vision, grain/optical
kernels, parity tests, owner review) → Phase C differentiation audit
(18-grids, overlap detection, manifestos, refinements only after approval) →
Phase D complete SwiftUI flows (Develop, Gallery, Print Room, Camcorder,
Camera, Account, Paywall, saving/sharing, StoreKit) → Phase E premium
refinement (Scene Analysis V2, camera-specific decisions, skin/subject,
Print Room realism, Camcorder temporal parity, accessibility, haptics,
motion, performance).

## 16. Reporting requirements

Every meaningful pass reports: what changed, why, which files, implemented vs
documented, tests run, passed, unverified, whether output changed (with
side-by-side images when it did), risks/tradeoffs, exact next step. Never
describe placeholders, copied assets, metadata, or architecture documents as
completed features. Never use "native" ambiguously — name SwiftUI / UIKit /
Core Image / Metal / Vision / AVFoundation / React Native / Skia / Expo.

## Final standard

Every camera has a point of view; the app understood the photograph; the
result was developed, not filtered; the interaction is tactile and
intentional; the output stays believable; the product rewards repeated use.

> A photographic instrument with enough intelligence to adapt, enough
> restraint to remain believable, and enough personality that every camera
> feels authored.
