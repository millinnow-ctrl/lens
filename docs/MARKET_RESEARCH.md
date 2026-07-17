# LensMood Market Research

Compounding research log per the Master Prompt §V. Every epic names its
differentiation in one sentence before code; the evidence for that sentence
lives here. Dated entries, newest first.

---

## 2026-07-17 — Round 1: market teardown + on-device AI capability survey

Two Research Fleet agents ran in parallel ahead of the develop-flow epic:
a market teardown of the film/retro-camera category (16 competitors) and a
survey of what photo-AI is actually shippable on-device in 2026. Full agent
reports summarized; strategic conclusions first.

### The differentiation sentence (ratified for the develop-flow epic)

> **"Filters guess. LensMood measures the light in your photo and develops it
> the way film actually would."**

No competitor can copy-paste it: Dazz can't say it (static overlays), RNI
can't (static LUTs from real emulsions), Dehancer can't (physics-informed but
100% manual per-image dialing), Halide won't (its brand is *anti*-processing).

### Headline findings

1. **Scene-adaptive film physics is unclaimed whitespace #1.** Every consumer
   app in the category applies the same LUT/overlay to every photo. The only
   physics claim in the market is Dehancer ("science-based" halation/bloom,
   $15/mo–$100/yr) — and it is a manual desktop-grade *editor* with zero scene
   understanding. Nobody detects the light in the frame and responds.
   LensMood's engine (flash reflectivity, source-colored neon bloom,
   directional noir, night reciprocity, day/night IR) already does the thing
   the market lacks; the epic's job is to make that felt in-product.
2. **The other whitespace, ranked:** (2) "18 cameras, one slider" curation —
   the market splits into buffet chaos (Dazz, hundreds of effects) and
   single-look apps (Huji); named, opinionated looks with one control matches
   the Fujifilm-recipe craze (800+ community recipes — "recipes for the light
   you're standing in"). (3) Import-first film treatment — import is
   universally the paywalled afterthought, yet it's where the photos are.
   (4) Privacy as headline — post-Meta/Apple scanning backlash, "scene-smart
   AND photos never leave the phone" is an empty position (Halide owns
   "anti-AI," which is adjacent, not this). (5) Honest lifetime pricing in a
   weekly-sub swamp. (6) Physically-grounded flash — flash is the signature
   of the disposable aesthetic AND a complaint magnet at the category leader.
3. **Universal complaints = cheap wins:** weekly-sub traps and trial traps
   (Dazz, VSCO, Tezza); nag screens after purchase (1998 Cam); silent devs +
   sudden breakage (NOMO, OldRoll); paywalled import/export/watermarks (Huji,
   Tezza, Fimo, RNI's reversed date-stamp fiasco); lost photos (Dazz).
   LensMood's counter-position: import and full-res export free forever,
   never upsell a paying user, photos land in the system library.
4. **Pricing the audience accepts:** casual band $9.99–24.99/yr or $15–20
   lifetime; craft apps (Halide) run $19.99/yr *plus* $59.99 lifetime — the
   respected dual offer. Weekly subs monetize impulse and poison reviews;
   free-forever+VC (Lapse, $42M) collapsed. **Recommended posture (gates
   stay OFF):** free tier with a few full cameras + full-res everything, then
   ~$19.99/yr and a $29–39 lifetime. Never weekly. "One-time purchase
   available" in the App Store subtitle converts in this exhausted market.
5. **Retention that works vs annoys:** loved — optional finite rolls
   (KD Pro's "reel of 24"), short skippable develop ritual, steady monthly
   camera drops (NOMO's engine, its complaint is drops are too rare),
   shareable named-look "camera cards" (Fuji-recipe culture retains without
   a network). Hated — forced social (Lapse −70% and retreat, Dispo dead,
   Hipstamatic's network: 16K downloads), streak pressure, delay-removal
   sold as a PRO perk, rate-us interruptions. **Do not build a social
   network.**
6. **Threat model:** Halide Mark III adding film looks (press machine,
   craft credibility) is the credible fast-follower; Dehancer adding scene
   analysis is second. The moat is per-look quality (fixture-parity
   discipline) and shipping scene-adaptive cameras first. Dehancer is the
   realism benchmark reviewers cite — LensMood must match or beat its
   halation/grain rendering, not just out-smart it.
7. **Tailwind:** the Gen-Z analog boom is measured, not vibes — ~42M active
   film-camera users, 35% aged 18–30 (2025); analog searches +41% YoY;
   mainstream business press covering the revival (Fortune, July 2026).

### On-device AI: what's real, what's refused

Cloud AI editors (Google Magic Editor, Picsart, Lensa) run their generative
stacks **in the cloud even on flagship devices**; instant/offline/private
optical intelligence is a lane they structurally cannot occupy. Apple's
generative APIs (Image Playground; ImageCreator is deprecated) are now
cloud-bound with usage limits — **LensMood refuses generative AI and should
market the refusal** (airplane-mode demo: everything still works).

Top three capabilities by wow-per-engineering-cost:

1. **Mask-aware light interaction — 0 MB shipped, highest wow-per-cost.**
   Fuse the existing scene-light meter (incl. chroma lights) with Apple's
   free mattes: rim-light/backlight-aware grading (halation blooms behind
   the subject where the meter found the source), skin-protected film curves
   via `semanticSegmentationSkinMatte` (the Photographic Styles trick, per
   film stock), sky-matte-scoped color. APIs: person segmentation (iOS 15),
   subject lift `VNGenerateForegroundInstanceMask` (iOS 17 feature-gate),
   semantic mattes (iOS 13+). ~10–50 ms, deterministic compositing.
2. **Depth-graded film optics — the flagship follow-up.** One depth map
   (AVDepthData when present; `apple/coreml-depth-anything-v2-small`,
   49.8 MB fp16, ~31–34 ms on ANE, as universal fallback for imports)
   feeding per-stock physically-shaped bokeh, **depth-graded halation**
   (bloom falls off with distance — nobody ships this), and depth-weighted
   atmosphere. Fits the existing ModelRegistry download path (iOS 16 floor).
3. **Data-true grain + halation.** FGA-NN-style parameter estimation from
   real film scans: a tiny network predicts parameters, the Metal shader
   stays the renderer — deterministic by construction. Highest cost (needs
   scan data + training), single-digit-MB payoff, and halation modeling is
   openly unsolved in the literature — a claimable first. Deferred until
   training infrastructure exists.

**Watchlist:** iOS 27 tap-to-segment (`GenerateIterativeSegmentationRequest`)
for "grade just this object"; iOS 26 lens-smudge detection; Foundation Models
for roll naming/search only (non-visual garnish). **Explicit no:** Image
Playground/generative face editing; neural relighting (2025–26 methods are
diffusion-based, non-deterministic, identity-risky — do physically
parameterized rim/halation from masks + depth instead).

**Determinism note for models:** a fixed Core ML model + fixed input is
reproducible per device/OS; pin compute units and record the model version
so renders stay re-derivable (aligns with the engine's determinism law).

### Decisions taken from this round

- Develop-flow epic proceeds under the ratified sentence above, with the
  Conductor and "For this photo" film matching at its heart.
- First AI build: **mask-aware light interaction** (0 MB, deterministic,
  extends the shipped light-physics passes). Depth model second, via the
  existing ModelRegistry. Data-true grain queued behind training infra.
- Monetization posture recorded above for the owner's eventual gate flip;
  gates remain OFF (`EVERYTHING_FREE_FOR_NOW`).
- Retention stack when the roadmap reaches rolls: optional rolls, short
  skippable ritual, monthly camera drops, shareable camera cards, no social
  graph, no streaks, never sell removal of an annoyance.

Full source lists live in the two agent reports (session archive); key
sources: Apple Core ML gallery / WWDC24–26 Vision & Core Image sessions,
FGA-NN (arXiv 2506.14350), BokehMe, ProMist-5K, Dehancer halation blog,
Appfigures (Hipstamatic), TechCrunch/Forbes (Lapse), justuseapp/Kimola
review mining (Dazz, OldRoll, 1998 Cam, Tezza, NOMO), Fuji X Weekly,
Fortune (2026-07-14) on the film revival.
