# LensMood — Profit Engine

The premium design: fully specified, wired in code with every gate hard-open
(`Store.everythingFreeForNow = true`, mirroring `EVERYTHING_FREE_FOR_NOW` in
`lensmood-native/src/store/store.tsx`). Nothing locks until the owner flips
the flag. Prices are the market-research bands; final price points are the
owner's call.

Evidence base (market research, July 2026): generous free tier + ~$19.99/yr
+ $29–39 lifetime is the winning structure for camera/film apps; weekly
subscriptions poison reviews and refund rates; paywalled import/export is
the #1 one-star trigger in the category; "one-time purchase" in the App
Store subtitle measurably converts. Conversion follows delight — a user who
has felt the transformation buys; one who hasn't, doesn't (same logic as the
first-shot-free aha in `docs/GROWTH_PLAYBOOK.md` §2).

---

## 1. The never-list (codified, non-negotiable)

1. **Never weekly.** No weekly subscription at any price, ever. Yearly and
   lifetime only.
2. **Never paywall import or export.** Picking a photo, saving, and sharing
   work identically at every tier. Full-resolution export is free forever —
   no "HD export" tier, no resolution cap, no export queue.
3. **Never nag a payer.** Once someone holds Plus (yearly or lifetime), the
   app never shows them an offer, a badge, an upsell row, or a "manage plan"
   prompt they didn't ask for. `AccountView` shows a thank-you line instead
   of the offer row.
4. **Never sell removal of an annoyance.** No watermark stamped on the
   user's photo at any tier. If a branded share-card format exists, the
   brand pill is part of that card's design at *every* tier including paid —
   it is a format you choose, never a mark you pay to erase. (This
   supersedes the free-export watermark in `GROWTH_PLAYBOOK.md` §3.)
5. **Never urgency or confirm-shaming.** No countdowns, no fake discounts,
   no "limited seats", no "No thanks, I hate my photos" dismiss copy, no
   pre-selected toggles, no full-screen paywall on launch.
6. **Never gate what shipped free.** Cameras in the free-forever set stay
   free forever. A gate flip may lock cameras that were never promised
   free, but nothing a user already relies on gets taken away.

---

## 2. Candidates, ranked by impact vs effort

Revenue is modeled **per 1,000 installs** with stated assumptions — no
fabricated download totals. Common assumptions unless noted: Apple Small
Business Program cut 15% (owner will qualify at launch); lifetime:yearly
buyer split 60:40 because lifetime is the highlighted offer; category-honest
payer conversion of installs at 1.5% (conservative) / 3% (base) / 5%
(strong) — these bracket published photo-app benchmarks; nobody should plan
on the strong case.

### Rank 1 — LensMood Plus: the signature camera set (impact HIGH, effort LOW)

**What:** one membership, two ways to buy (yearly ~$19.99, lifetime
~$34.99). Plus holds the 12 signature cameras; 6 full cameras are free
forever (see §3). No feature crippling anywhere — the gate is *which
cameras*, never *what the app does to a photo*.

**Why delight-first:** every camera is a fully authored instrument (the
looks are the product — `MASTER_DIRECTIVE.md` §1). Free users get six
complete, uncrippled instruments at full resolution; the purchase is "I
want more cameras," which is desire, not ransom. Locked cameras stay
visible and honestly labeled — tap one and the paywall states plainly what
it is and what stays free.

**Effort:** low — the 18 cameras exist (engine workstream); the gate is a
set membership check that is already wired (`PlusCatalog` in
`Sources/Services/Store.swift`).

**Revenue model, per 1,000 installs, year one, net of 15%:**

| Scenario | Payers | Lifetime (×$34.99) | Yearly (×$19.99) | Gross | Net |
|---|---|---|---|---|---|
| Conservative 1.5% | 15 | 9 → $314.91 | 6 → $119.94 | $434.85 | ≈ $370 |
| Base 3% | 30 | 18 → $629.82 | 12 → $239.88 | $869.70 | ≈ $739 |
| Strong 5% | 50 | 30 → $1,049.70 | 20 → $399.80 | $1,449.50 | ≈ $1,232 |

Year two adds yearly renewals only (assume 40% renewal — honest for a
utility with no subscription-only feature): base case ≈ $82 net per
original 1,000 installs. Lifetime-heavy mix trades recurring revenue for
goodwill and reviews; that is the intended trade at this stage.

### Rank 2 — Seasonal camera drops (impact HIGH, effort MEDIUM-HIGH)

**What:** 2–4 new cameras per year (e.g. a summer instant stock, a winter
tungsten stock), each a real authored identity passing the same parity and
differentiation bar as the launch 18 (`MASTER_DIRECTIVE.md` §6–7). Drops
land in Plus. Every drop is also free for everyone to *try* on their own
photo with full-quality preview — the aha is never gated, only keeping it.

**Why delight-first:** drops are a gift cadence, not a drip-feed of
withheld content — the launch product is complete without them. They give
yearly members a concrete renewal reason and non-payers a recurring,
honest conversion moment.

**Effort:** medium-high — each camera is real engine work with fixtures
and owner approval; this is a content pipeline, not a SKU.

**Revenue model (uplift, not a SKU):** assume each drop converts an extra
0.3–0.7% of the existing install base during drop week (assumption, not
data) and lifts yearly renewal from ~40% toward ~55%. Per 1,000 installs:
roughly +$75–170 net/year across 3 drops in the base case. Model it as the
thing that makes yearly worth keeping, not as standalone income.

**Honesty note:** lifetime includes all future drops (recommended — see
§3). That caps drop revenue to non-payers + renewals; the alternative
(drops sold separately to lifetime holders) violates never-nag-a-payer and
is rejected.

### Rank 3 — Tip jar (impact LOW, effort TRIVIAL)

**What:** three consumable IAPs ($2.99 / $4.99 / $9.99) on a single quiet
row in `AccountView` ("Leave a tip in the darkroom"), visible only after a
user has developed at least a few photos. No perks, no unlock — stated
plainly.

**Why delight-first:** it is the purest conversion-follows-delight
mechanic; it monetizes gratitude without touching the product.

**Revenue model:** assume 0.3–0.8% of installs tip once, average $4.50:
per 1,000 installs ≈ $13–36 gross, ≈ $11–31 net. Negligible by design —
ship it for the goodwill signal, not the money. (Deferred to a follow-up
pass; not wired yet, so launch surface stays minimal.)

### Rank 4 — Roll printing / physical prints (impact UNKNOWN, effort VERY HIGH) — defer

**What:** the Print Room's photographed-object output as real shipped
prints (a "roll" of 10–20). Fits the product soul perfectly.

**Why deferred:** requires a fulfillment partner, physical QA, shipping
support, and regional pricing — an operations business bolted onto a
one-person app. Unit economics at typical print-API costs ($6–9 per
10-pack shipped, retail $14.99): ≈ $5–8 margin per order before Apple/
payment questions are even settled (physical goods may use external
payment, which is its own compliance project). Assume 0.5–1% of active
users order per quarter — per 1,000 installs that is single-digit orders.
Revisit when there is a retained user base to sell to.

### Rejected outright

- **High-res export tiers** — violates never-list #2. Full resolution is
  free forever. (Answering the brief's open question with a hard no.)
- **Watermark removal as a product** — violates never-list #4.
- **Credit meters on developing** (the reference app's 5/month) — replaced
  by the camera-set gate. A metered darkroom punishes exactly the repeated
  use the product is designed to reward (`MASTER_DIRECTIVE.md` final
  standard). The free tier is "six cameras, unlimited, full-res," not
  "eighteen cameras, five times."

---

## 3. Recommended launch configuration

**Free forever (the demo that never expires):**

- 6 full cameras, chosen to span the aesthetic range so the free app is a
  real product, and each a proven sharer:
  `disposable`, `camcorder-90s`, `leica-street`, `polaroid`, `film-noir`,
  `tokyo-neon`
  (party flash, video-era tape, classic street, instant, monochrome, night
  neon — one credible answer for almost any photo.)
- Full-resolution export of everything, photo and video. Import, save,
  share: all free, all tiers, forever.
- Full develop controls and decision notes on free cameras — no crippled
  sliders.
- Every locked camera remains browsable with its card, personality line,
  and an on-your-photo preview — the aha is free; keeping the developed
  file at full res on a Plus camera is what Plus is for.

**LensMood Plus (both offers unlock the identical thing):**

- The 12 signature cameras: `iphone-flash`, `gq-editorial`, `a24-still`,
  `y2k-digicam`, `super-8`, `lomo`, `kodachrome`, `security-cam`,
  `point-shoot`, `pastel-cinema`, `photobooth`, `tintype`.
- All future seasonal camera drops.
- Nothing else — no "priority" anything, no cosmetic ransom. Plus is more
  instruments, full stop.

**Offers:**

| Offer | Product ID | Price band | Framing |
|---|---|---|---|
| Yearly | `app.lensmood.ios.plus.yearly` | ~$19.99/yr | "Billed once a year through your Apple ID" |
| Lifetime (highlighted) | `app.lensmood.ios.plus.lifetime` | ~$34.99 | "One-time purchase — yours for good, future cameras included" |

Lifetime sits inside the research's $29–39 band and prices at ~1.75× the
yearly so the yearly still reads as sane. The paywall shows both side by
side, lifetime visually primary, restore button always present, zero
urgency mechanics.

**App Store subtitle (30-char limit):** `18 cameras. One-time purchase.`
(exactly 30 characters). Keeps the research-validated phrase in the
highest-converting slot; the previous candidate ("Shot on the camera it
deserved") moves to promo text if wanted.

**Gate-flip behavior (when the owner sets `everythingFreeForNow = false`):**
locked set becomes exactly `PlusCatalog.plusStockIDs` for `free`
entitlement and empty for `plus`; the paywall becomes reachable from a
locked camera card; `AccountView` swaps the preview row for the real offer
row for free users and a thank-you row for members. No other behavior in
the app changes — that surface area is the whole point.

---

## 4. What is wired vs documented

Wired now, gates OFF (see `LensMoodApp/Sources/Services/Store.swift`,
`PaywallView.swift`, `AccountView.swift`):

- StoreKit 2 catalog (yearly + lifetime IDs), entitlement model
  (`free`/`plus`), transaction listener, restore, and the single global
  gate `Store.everythingFreeForNow = true` honored by every lock check.
- Paywall built to the design above; unreachable in normal flow while
  gates are off; reachable from `AccountView` → "Preview the supporter
  offer" for design review. Degrades gracefully with clearly-marked
  placeholder prices while no App Store Connect products exist.
- Tests: entitlement logic (gates off ⇒ nothing locked; simulated gate-on
  ⇒ exactly the Plus set locked for free, nothing for plus), catalog
  integrity, copy hygiene scan of all Sources.

Documented only (not wired): tip jar, seasonal-drop pipeline, roll
printing, the App Store Connect product setup itself (needs the paid Apple
account), and the locked-camera preview flow on Home/Develop (owned by
other workstreams; the gate API they will call — `Store.isUnlocked(_:)` —
exists and currently always returns true).

## 5. Decisions reserved for the owner

1. Final price points within the bands ($19.99/yr and $34.99 lifetime are
   recommendations, not commitments) — set in App Store Connect, never
   hard-coded.
2. The gate flip itself (`Store.everythingFreeForNow`), after pricing is
   decided at the end, per `CLAUDE.md`.
3. Apple Developer Program enrollment + App Store Connect product creation
   (two products, one subscription group for the yearly) and Small
   Business Program enrollment for the 15% rate.
4. Whether lifetime's "future cameras included" promise ever gets revised
   for cameras not yet announced (recommendation: don't).
5. Free-forever set membership — the six above are a recommendation; the
   set is one line in `PlusCatalog`.

---

## 6. Council ruling, 2026-07-18 (RECOMMENDATION — owner decides pricing and the flip)

Dated addendum. Nothing above this line is rewritten; where this section
differs (the lifetime price), this is the newer recommendation and the
owner arbitrates.

**Preview flow status change.** The §3 on-your-photo preview flow is now
**WIRED** (was "documented only" in §4):

- Locked cameras develop **fully** — full ceremony, full quality, on the
  user's own photo. The gate sits at **Save/Share**, never at the aha.
- Locked develops **never enter the roll** — "the roll keeps what you
  keep."
- The paywall carries the **user's own frame**, not stock art.
- Paywall surfaces are exactly two: `develop-keep` and `account`.
  Nothing else in the app ever presents an offer.
- All of it is inert while `Store.everythingFreeForNow = true`.

**Price RECOMMENDATION: $19.99 yearly / $49.99 lifetime** (lifetime was
~$34.99 in §3). The honest rationale: at $34.99 the lifetime nets
≈ $29.75 after the 15% cut, versus ≈ $28 expected yearly LTV [believed:
category renewal assumptions per §2 — first year net ≈ $17 plus ~40%
renewal tail]. A forever-promise priced ~6% above one expected
subscriber cannibalizes the compounding SKU. Halide sustains a $59.99
lifetime beside the same $19.99 yearly [researched: market teardown,
`docs/MARKET_RESEARCH.md` finding 4]. $49.99 keeps lifetime ≈ 2.5× the
yearly, inside the respected craft-app pattern. **No launch discount, no
founders' window** — prices lower easily, raise expensively, and an
owned camera's price doesn't wobble.

**Drop cadence.** The first seasonal drop opens cycle 2 (~day 120 after
launch). The **public** cadence promise is capped at 2 drops/year
[believed: sustainable for one owner]; anything above that is upside,
never a commitment.

**Floor math, on record** [believed: assumptions stated, no install
data exists yet]:

- ~30% of installs reach the warm paywall — composed of 60% of users
  developing ≥3 photos × half of those meeting a ranked-locked #1 camera
  and tapping Keep.
- × ~5% paywall conversion ≈ **1.5% overall payer conversion** — the
  conservative bracket already used in §2.
- **Watch trigger:** if App Store Connect conversion sits below ~1.5% at
  week 4, the stage-resolution-only preview mitigation returns to the
  table (locked previews develop at stage resolution rather than full).
  Never a watermark, never a degraded render — the never-list holds.
