# LensMood — Growth Playbook

The strategy behind the product decisions, written the way a growth
consultant would hand it over. July 2026.

## 1. Positioning (one sentence)

**LensMood turns any camera-roll photo into a shot from a real camera era —
in seconds, on your phone, nothing uploaded.**

The three words that must survive every rewrite: *camera roll* (input is
photos people already have), *era* (nostalgia, not "filters"), *on your
phone* (privacy + speed + zero marginal cost).

## 2. The one metric that matters

**Time-to-aha: seconds from first open → user sees THEIR photo developed.**

Everything else (retention, sharing, conversion) is downstream of this
moment. Target: **under 15 seconds**. The funnel before this change:

    open app → scroll home → find studio → pick photo → pick style
    → SPEND A CREDIT → aha              (6 steps, meter anxiety at step 6)

After this change:

    open app → welcome sheet → pick photo → aha (first shot free)

Shipped mechanics:
- **First-run welcome** (one screen, never twice): "Pick a photo — we'll
  shoot it on 18 cameras. First shot's on us." Straight into the picker.
- **First shot always free** (`Studio.beginGeneration`): the aha never
  sits behind the meter. A user who has felt the transformation values
  the 5 monthly credits; one who hasn't, doesn't.

## 3. The loop (already live, keep tuning)

Acquisition → aha → share card (story/split, watermarked on free) →
viewer taps through → their aha. Retention: daily free look + streak +
the 18-slot case + post-export "tomorrow's look" hook.

The watermark on free exports IS the acquisition channel. Never make it
ugly enough to crop or subtle enough to miss — current brand pill is right.

## 4. Pricing notes

> **Amendment 2026-07-18:** the tier ladder below described the frozen
> reference app and is superseded by `docs/PROFIT_ENGINE.md` (Plus:
> $19.99 yearly / $49.99 lifetime RECOMMENDATION, never-list, no credit
> meters, no paid watermark removal). Kept for history.

- Tier ladder is sound ($0 / 7 / 15 / 29). Creator at $7 is the volume
  tier; Studio at $29 exists mostly to anchor Creator as cheap.
- Free = 5 shots/month + watermark + first shot free. Resist raising free
  credits: the daily free look already gives infinite-but-rationed value.
- On iOS everything must route through Apple IAP (see APP_STORE_CHECKLIST).
- Next experiment when there's traffic: 7-day Creator trial vs first-shot
  -free only. Run one at a time.

## 5. ASO system (council ruling, 2026-07-18)

This section supersedes the earlier §5 listing draft ("LensMood —
Aesthetic Camera" / "Shot on the camera it deserved" / the old keyword
string). ASO here is an *iterated system* with a measurement loop, not a
one-time paste. All copy below is paste-safe for App Store Connect.

- **Title (30-char limit):** `LensMood — Film Camera` — brand + head
  term, 22 chars [measured: character count]. Replaces "LensMood —
  Aesthetic Camera" [researched: head-term titles dominate the category
  shelf — the top results for the category's money searches carry the
  head term in the title, not a vibe word].
- **Subtitle (30-char limit):** `18 cameras. One-time purchase.` — ONLY
  once the lifetime IAP is live and buyable. Until then, the neutral
  fallback already specified in `docs/LAUNCH_RUNBOOK.md` §5 (e.g.
  `18 film cameras. On-device.`) [measured: the 2.3 metadata-accuracy
  risk of naming a purchase that doesn't exist is flagged in the runbook
  itself].
- **Keyword field (100-char limit; no words already in the title; no
  trademarks):**
  `disposable,vintage,retro,vhs,y2k,grain,analog,noir,instant,90s,camcorder,develop,darkroom`
  — 89 chars [measured: character count]. "film" and "camera" are
  excluded on purpose: title words are already indexed and duplicating
  them wastes the field [researched: standard ASC indexing behavior].
- **Screenshot storyboard** (first three carry the search impression
  [researched: ASC search results show up to three portrait shots]):
  1. Split-compare with caption `Filters guess. This one measured the
     light.`
  2. The two-light pair — same camera, noon vs night, two different
     develops (pair-mode export from `ui-artifacts/share-cards/`,
     produced by the Light Test card build).
  3. The 18-camera home shelf.
  4. The "For this photo" ranking on the develop screen.
  5. Privacy: `Your photos never leave your phone.`
  6. Tape / Print Room.
- **Iteration loop:** monthly Apple Product Page Optimization test on
  screenshot #1 (split-compare vs the two-light pair — which opening
  frame converts impressions better); keyword-field rotation judged
  against App Store Connect search-impression data each cycle. All
  measurement is Apple-side only — no analytics SDKs, ever (standing
  law; the privacy label is the product).
- **Creator seeding:** one named format — the **"light test"**: same
  photo (or two photos), one camera, watch it develop differently, the
  decision note visible on screen. First batch is **5 gifted lifetime
  promo codes** (not 15) to film/Y2K-niche micro-creators whose visible
  practice is *simulation* (recipe/digicam content), NOT chemical-film
  communities; the remaining 10 codes go out only after at least 3 of
  the 5 post willingly. Each creator gets a Custom Product Page link so
  attribution is Apple-side, per the measurement law above. Explicitly:
  **no seeding in r/AnalogCommunity** [believed: simulation apps read as
  provocation there; the sub's culture is chemical process, not looks].
- **Review ask:** `SKStoreReviewController` after the **3rd saved
  develop AND ≥5 days since install**, at the post-save quiet moment —
  never mid-flow, never on a timer. (This documents the policy; the code
  change, if any, is a later cycle.)

## 6. Launch sequence (first 30 days)

> **Amendment 2026-07-18:** creator counts and format below are
> superseded by §5's creator-seeding rules (5 gifted lifetime codes
> first, "light test" format, no r/AnalogCommunity) and by the dated
> launch schedule in `docs/LAUNCH_RUNBOOK.md` §13. Kept for history.

1. **Week 1 — TikTok/Reels seeding:** 10-15 creators in the film-photo /
   Y2K niche, gifted Creator. Ask for one format only: camera-roll photo →
   deck spin → develop → before/after. The app's own share cards are the
   b-roll.
2. **Week 2 — "guess the camera" hook:** post developed shots, comments
   guess which of the 18 looks. Zero-budget engagement format.
3. **Week 3-4 — TestFlight → App Store**, leaning on the privacy angle
   ("the photo app that never sees your photos") for press/newsletters.

## 7. Measurement without breaking the privacy promise

The privacy page says no analytics — that's a feature, keep it. Measure
with what leaks naturally: App Store impressions→downloads, watermark-card
impressions (creator posts), TestFlight feedback, and a single opt-in
"How did you find LensMood?" question post-first-export if needed later.

## 8. Risks, ranked

1. **Trademark style names** (Polaroid, Leica, A24, GQ, Kodachrome…) —
   rename before App Store submission (map in APP_STORE_CHECKLIST).
2. **Aha under-delivery on bad photos** — heavy looks now carry curves/
   split-tones so even flat photos transform; keep testing on dim indoor
   shots, not just golden-hour samples.
3. **Free-tier arbitrage** (clear data → infinite first shots) — accepted
   for now; local-only data makes this unfixable without accounts, and the
   people who bother were never buyers.
