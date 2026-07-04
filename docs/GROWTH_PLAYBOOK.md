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

- Tier ladder is sound ($0 / 7 / 15 / 29). Creator at $7 is the volume
  tier; Studio at $29 exists mostly to anchor Creator as cheap.
- Free = 5 shots/month + watermark + first shot free. Resist raising free
  credits: the daily free look already gives infinite-but-rationed value.
- On iOS everything must route through Apple IAP (see APP_STORE_CHECKLIST).
- Next experiment when there's traffic: 7-day Creator trial vs first-shot
  -free only. Run one at a time.

## 5. App Store listing (ready to paste)

- **Name (30ch):** `LensMood — Aesthetic Camera`
- **Subtitle (30ch):** `Shot on the camera it deserved`
- **Keywords (100ch):** `film,camera,filter,vintage,disposable,y2k,vhs,noir,retro,aesthetic,grain,photo editor,preset`
- **Screenshot storyboard (6):** 1) before/after split "The $7,000 look,
  from your camera roll" 2) the 18-look deck 3) AF·FACE viewfinder +
  sliders "Real controls, real film math" 4) story-card export 5) daily
  free look + streak 6) privacy: "Nothing uploads. Ever."
- **Promo text:** New: 18 camera looks, on-device face-aware flash, and
  story-ready exports. First shot's on us.

## 6. Launch sequence (first 30 days)

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
