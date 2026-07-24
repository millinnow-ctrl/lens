# LensMood — Launch Runbook

The complete, ordered path from today's repo to the App Store for the
SwiftUI app in `LensMoodApp/` (bundle id `app.lensmood.ios`). Steps marked
**[OWNER]** require the Apple account holder and cannot be done by an
agent or CI. Everything else is already in the repo or scriptable.

Companion docs: `docs/PRIVACY_POLICY.md` (the policy text to host),
`docs/PROFIT_ENGINE.md` (pricing design), `docs/APP_STORE_CHECKLIST.md`
(status snapshot pointing here).

---

## 0. What the code already satisfies (verified in repo)

- Three targets (`LensMood`, `LensMoodShare`, `LensMoodWidgets`) each
  declare `ITSAppUsesNonExemptEncryption: false` — the export-compliance
  question is answered in the binary; uploads never stall on it.
- App target: `CFBundleDisplayName` (LensMood), `UILaunchScreen: {}`,
  portrait-only iPhone (`TARGETED_DEVICE_FAMILY: 1`), 1024px AppIcon in
  the asset catalog, `lensmood://` URL scheme for widget deep links.
- Permission strings: camera, microphone, photo-library **add-only** on
  the app; add-only Photos on the share extension. Import uses the system
  photo picker (no read permission ever requested).
- `PrivacyInfo.xcprivacy` in all three targets: no tracking, no data
  collection, UserDefaults CA92.1 (required-reason audit is in the file's
  comment).
- Share extension activation rule is a bounded predicate (one image), not
  `TRUEPREDICATE`.
- StoreKit 2 plumbing exists but every gate is open
  (`Store.everythingFreeForNow = true`); in **release builds the paywall
  is unreachable unless real App Store products load**, so a reviewer can
  never see placeholder prices. (Debug builds always show the
  Account-screen preview row for design review.)
- No analytics, no networking, no third-party SDKs, no account system —
  the App Privacy answer is genuinely "Data Not Collected".

---

## 1. Apple Developer Program **[OWNER]**

1. Enroll at developer.apple.com with your Apple ID ($99/yr). Individual
   enrollment is fine (the seller name will be your personal name).
2. While it processes (usually <48h), nothing else on this list is
   blocked except signing and App Store Connect.
3. **Small Business Program** (15% commission instead of 30%): enroll at
   App Store Connect → Business → App Store Small Business Program
   *after* your first paid agreement is active. Do this before the gate
   flip (§10); it is not needed for a free v1.

## 2. Agreements, tax, banking **[OWNER]**

In App Store Connect → Business:

- Accept the free-apps agreement (required to ship anything).
- Complete the **Paid Applications** agreement + banking + tax forms —
  only required before IAPs go live (§10), but the review of these forms
  can take days, so file them early.

## 3. Signing — Xcode automatic signing **[OWNER machine]**

1. On the Mac: clone the repo, `brew install xcodegen`, then in
   `LensMoodApp/` run `xcodegen` and open `LensMood.xcodeproj`.
2. For each of the three targets → Signing & Capabilities: check
   "Automatically manage signing", select your team. Xcode registers the
   three bundle ids (`app.lensmood.ios`, `.share`, `.widgets`) and mints
   certificates/profiles. No extra capabilities are needed — the app uses
   no App Groups, no push, no iCloud.
3. Note: `project.yml` carries no team id on purpose (CI builds
   unsigned). If regenerating with xcodegen wipes your team selection,
   either re-pick it in Xcode or add
   `DEVELOPMENT_TEAM: <TEAMID>` under each target's settings locally.

## 4. Host the privacy policy **[OWNER]**

Apple requires a public privacy policy URL. `docs/PRIVACY_POLICY.md` is
the finished text — replace `OWNER-EMAIL` and the effective date, then
host it anywhere public. Easiest: GitHub Pages (Settings → Pages →
deploy from a `docs/` branch folder, or a one-page repo). Keep the URL
stable; it goes into App Store Connect in §5.

## 5. Create the app in App Store Connect **[OWNER]**

App Store Connect → My Apps → "+" → New App:

| Field | Value |
|---|---|
| Platform | iOS |
| Name | LensMood |
| Primary language | English (U.S.) |
| Bundle ID | app.lensmood.ios (appears after §3 registers it) |
| SKU | lensmood-ios-001 (any stable string) |
| Access | Full |

Then on the App Information / version pages:

- **Subtitle**: `18 cameras. One-time purchase.` (exactly 30 chars).
  **Caveat**: if you submit v1 with *no* IAP configured (everything free,
  gates open), "One-time purchase" describes a product that isn't buyable
  yet and risks a metadata-accuracy flag (2.3). Either create the
  lifetime IAP with v1 (§10 can be done pre-flip; the paywall then shows
  real prices) or launch with a neutral subtitle (e.g.
  `18 film cameras. On-device.`) and switch when the gate flips.
- **Category**: Photo & Video. Secondary: none needed.
- **Privacy Policy URL**: from §4. Support URL: same page or the repo.
- **Price**: Free (v1 ships with all gates open).
- Content rights: no third-party content.

> **Council RECOMMENDATION, 2026-07-18 — the owner decides all of this;
> nothing here is self-executing.**
>
> - **Gate ON before public visibility**: flip
>   `Store.everythingFreeForNow = false` as the **last pre-submission
>   step**, so the app is never publicly visible in its all-free state.
> - **Products** (create per §10): `app.lensmood.ios.plus.yearly` at
>   **$19.99/yr** and `app.lensmood.ios.plus.lifetime` at **$49.99**,
>   lifetime visually primary on the paywall.
> - **No launch discount, no founders' window** [council ruling;
>   rationale in one line: prices lower easily, raise expensively — and
>   an owned camera's price doesn't wobble].
> - Subtitle rule unchanged: `18 cameras. One-time purchase.` only with
>   a live IAP; otherwise the neutral fallback above.
> - If the owner declines gate-ON at launch, the fallback is the
>   **founding roll** (§12a) — not a silent later flip.

## 6. App Privacy questionnaire **[OWNER]**

App Store Connect → App Privacy. The truthful answers for this app:

1. "Do you or your third-party partners collect data from this app?" →
   **No, we do not collect data from this app.**
2. That's the whole questionnaire — the label renders as **"Data Not
   Collected"**. Do not add ATT; there is no tracking.

If purchases are added later, this answer does **not** change: StoreKit
purchases are processed by Apple, not "collected by you". Revisit only if
analytics, accounts, or any networking SDK ever ships.

## 7. Age rating **[OWNER]**

App Store Connect age-rating questionnaire — answer **None / No** to
every content category (violence, sexual content, profanity, horror,
gambling, contests, medical, alcohol/tobacco/drugs), **No** to
unrestricted web access, **No** to user-generated content features with
sharing to others (photos stay local; the share sheet is the OS's), and
**No** to advertising. Result: **4+** (12+ nothing applies). The camera
photographs whatever the user points it at — that is not UGC in Apple's
sense and needs no moderation answer.

## 8. Build, upload, TestFlight

1. Bump if needed: `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in
   `LensMoodApp/project.yml` (all three targets share the values — keep
   extension versions identical to the app or App Store validation
   fails).
2. **[OWNER machine]** `xcodegen` → Xcode → Product → Archive (scheme
   LensMood, Any iOS Device) → Distribute App → App Store Connect →
   Upload. Automatic signing handles profiles. (The repo's
   `testflight.yml` workflow builds the *frozen reference app* via EAS —
   it is not the Swift app's path; a Mac-runner upload workflow can be
   added later with ASC API-key secrets.)
3. Export compliance: no question appears — answered in the binary
   (`ITSAppUsesNonExemptEncryption=false`; the app uses only exempt
   HTTPS/system crypto, and today ships no networking at all).
4. TestFlight → internal testing → add yourself. **Device pass** (the
   real acceptance gate, per `docs/TESTING.md` culture):
   - All five tabs: Cameras, Capture, Library, Print, Tape.
   - Capture: camera permission prompt appears once, copy reads right;
     denial leaves the app usable.
   - Tape: camera + microphone prompts; record, develop, save.
   - Save from Develop: add-only Photos prompt; photo lands in Photos.
   - Share extension: share a photo from Photos → LensMood → develop →
     save.
   - Widgets: add Home Screen + Lock Screen widgets; tapping deep-links
     to the right camera.
   - Account sheet: in this TestFlight (release) build with no products
     configured, the supporter-offer row must be **absent**.
   - Cold-launch performance, memory pressure on a big import, dark
     mode, Dynamic Type sanity.

   **Device-pass additions (council amendment, 2026-07-18):**

   1. **Masked-light matrix.** Develop a fixture set spanning diverse
      skin tones × dim/bright lighting — explicitly including **dark
      skin in dim light** — on a physical device, where person
      segmentation returns real mattes, and eyeball skin protection and
      rim behavior on each. This validates the cycle-1 skin-mask bug fix
      on real Vision output; CI cannot cover it [measured: simulator
      segmentation output is empty — see item 2].
   2. **Ad-material re-capture.** Re-run the ad/matte exports on the
      device so every marketing asset that claims mask-driven behavior
      (the depth-parallax video above all) is built from real mattes.
      Simulator matte exports are empty [measured: ci-captures
      ad-material run, max pixel 3/255] — assets built from simulator
      renders **may not ship with mask-behavior claims** (§16 honesty:
      that would be belief dressed as fact). The blocked-asset list
      lives in `docs/PRESS_KIT.md`.
   3. **Print + Tape maintenance QA.** Full pass of both tabs every
      release: record/develop/save on Tape, the Print Room object end to
      end. Zero cycle-1 feature work on either; bugs fixed at parity.
      Maintenance ≠ abandoned — Tape stays in metadata and screenshots
      as shipped.

## 9. Screenshots + metadata **[OWNER approves, capture is scriptable]**

Current App Store Connect rules (2026): one set of **6.9" iPhone**
screenshots is required (1320×2868 portrait; iPhone 16/17 Pro Max
simulator). Optionally add a **6.5"** set (1242×2688) for older devices —
otherwise ASC scales the 6.9" set. iPhone-only app → no iPad set. Up to
10 images; the first three carry the search impression.

Capture (simulator is fine — `xcrun simctl io booted screenshot`):

1. Cameras (Home) — the film rail, hero card.
2. Develop — mid-ceremony or the finished frame with decision notes
   (the product's proof moment; consider making this #1).
3. Capture — the viewfinder instrument.
4. Library — a filled roll.
5. Print — the Print Room object.
6. Tape — the camcorder surface.

Plus: promotional text (170 chars, changeable anytime), description,
keywords (100 chars — e.g. `film,camera,grain,analog,vintage,photo,
develop,disposable,instant,vhs`), "What's New".

## 10. In-App Purchases **[OWNER]** — with v1 or at gate-flip

Create in App Store Connect → the app → Monetization:

| Product | Type | Product ID (must match `Store.swift`) |
|---|---|---|
| LensMood Plus — Yearly | Auto-renewable subscription, 1-year, in a new group "LensMood Plus" | `app.lensmood.ios.plus.yearly` |
| LensMood Plus — Lifetime | Non-consumable | `app.lensmood.ios.plus.lifetime` |

- Price bands per `docs/PROFIT_ENGINE.md` §3 (~$19.99/yr, ~$34.99
  lifetime) — final points are the owner's call, set here, never
  hard-coded. **Amendment 2026-07-18:** the council RECOMMENDATION
  revises lifetime to **$49.99** (yearly stays $19.99); rationale and
  floor math in the dated addendum at the end of
  `docs/PROFIT_ENGINE.md`. Owner decides.
- Each product needs display name, description, and a review screenshot
  (a paywall screenshot works).
- **Auto-renewable extras**: App Store Connect requires a Terms of Use
  (EULA) link for subscriptions — Apple's standard EULA is acceptable;
  the paywall copy already states billing cadence and cancellation.
- IAPs submit **with an app version** the first time — tick them on the
  version page.
- Small Business Program (§1) before these go live.

## 11. Review notes + submit **[OWNER]**

Paste into App Review notes:

> All photo and video processing happens entirely on device (Core Image /
> Metal / Vision / AVFoundation). Nothing is uploaded; the app has no
> server and no account system — no login is needed to use every feature.
> The Capture tab uses the camera; the Tape tab records video and
> therefore uses the camera and microphone. Saving uses add-only Photos
> access; importing uses the system photo picker. The app is fully
> functional offline. No demo account is required.

Then: select the build, submit. First reviews typically land in 24–48h.
Choose manual or automatic release; manual is safer for a first launch.

## 12. Gate flip — turning monetization on (later) **[OWNER decides]**

When pricing is decided (per `CLAUDE.md`, at the end):

1. Complete §2 paid agreement, §10 products, Small Business Program.
2. Flip `Store.everythingFreeForNow` to `false` in
   `LensMoodApp/Sources/Services/Store.swift` — the single switch. The
   locked set becomes exactly `PlusCatalog.plusStockIDs` for free users;
   AccountView swaps the preview row for the real offer/thank-you rows.
3. Verify the never-list holds (`docs/PROFIT_ENGINE.md` §1): six free
   cameras stay free, import/export/full-res never gated, no upsell to
   members.
4. Run `ProfitEngineTests` (gate simulation is covered) + a device pass
   of buy/restore in TestFlight sandbox.
5. Update subtitle/description to the one-time-purchase framing if §5's
   neutral subtitle was used.
6. Submit as a normal version update; in review notes state which
   cameras are paid and that previously-free cameras remain free.

### 12a. Fallback if the owner declines gate-ON at launch: the founding roll (council amendment, 2026-07-18)

This replaces any reading of this section as a quiet later flip. If v1
ships all-free and the gate flips in a later version:

- **Every install before the flip date keeps all 18 cameras forever.**
  Entitlement by install date; nothing anyone already holds is taken
  away (never-list #6 in `docs/PROFIT_ENGINE.md`, applied to the whole
  catalog for early users).
- The flip release notes state it as **plain thanks** — "early
  developers keep all 18, with thanks" — not as a promotion.
- The subtitle stays **neutral until the IAP exists** (§5 rule).
- **No dated in-listing removal promises** ("free until August!") —
  pre-announced loss is still loss, and it reads as urgency mechanics,
  which the never-list bans.

## 13. Launch schedule (council amendment, 2026-07-18)

Dates are relative to App Review approval; the calendar date is the
owner's decision (RECOMMENDATION only).

- **Day −2 (at App Review approval):** submit the Apple featuring
  nomination — draft paragraph in `docs/PRESS_KIT.md`. Featuring lead
  time runs in weeks, and a nomination amplifies nothing by itself, so
  it costs nothing to file early.
- **Day 0:** public launch (manual release per §11). **Quiet period: 7
  days** — no press, no seeding — conditional on the §8 masked-light
  matrix having run on a physical device. **If it has not run, hold 14
  days** [the guarded failure class: device-only rendering defects with
  zero CI coverage — exactly what §8 items 1–2 exist to catch].
- **Day 8:** press emails (`docs/PRESS_KIT.md`) + Product Hunt + the
  first creator batch (5 lifetime codes per `docs/GROWTH_PLAYBOOK.md`
  §5), coverage landing days 9–14.
- Review-prompt policy as in `docs/GROWTH_PLAYBOOK.md` §5: the prompt
  needs installs that are ≥5 days old — another reason press waits for
  day 8 (early organic installs can leave reviews before the coverage
  wave arrives).

## 14. Owner-decision checklist (added 2026-07-18)

Everything on this list belongs to the owner; agents prepare, the owner
decides.

- [ ] **Pricing** — accept/adjust $19.99 yearly / $49.99 lifetime
      (council RECOMMENDATION, §5 block + `docs/PROFIT_ENGINE.md`
      addendum).
- [ ] **The gate flip** — gate-ON pre-submission (recommended) or the
      founding roll (§12a).
- [ ] **ASC product creation** (§10) + **subtitle choice** (§5 rule:
      purchase subtitle only with a live IAP).
- [ ] **Small Business Program** confirmation before any paid product
      goes live (§1).
- [ ] **§8 device pass** — the base list + masked-light matrix +
      ad-material re-capture + Print/Tape QA.
- [ ] **Launch date + quiet-period length** (7 days with the matrix
      run; 14 without — §13).
- [ ] **Featuring nomination** submission (§13, draft in
      `docs/PRESS_KIT.md`).
- [ ] **Press send** (day 8, `docs/PRESS_KIT.md`).
- [ ] **Approvals still pending from cycle-1 builds:** the paywall
      keep-context layout, the Light Test card design, and the grain
      stage-1 side-by-side grids — review artifacts under
      `ui-artifacts/` (share cards in `ui-artifacts/share-cards/`).
- [ ] **Any future analytics sink** — adding one is a privacy-label
      change and breaks "Data Not Collected" (council recommends:
      never).

---

## Quick owner-only summary

| Step | Only the owner can do it |
|---|---|
| §1 Developer Program + Small Business enrollment | Yes — Apple ID, payment |
| §2 Agreements/tax/banking | Yes |
| §3 Signing team selection | Yes — needs the membership on a Mac |
| §4 Hosting the privacy policy | Yes — public URL under owner control |
| §5–7 ASC app, privacy answers, age rating | Yes — ASC access |
| §8 Archive/upload + device pass | Yes (Mac + device) |
| §9 Final screenshot/metadata approval | Yes (capture is scriptable) |
| §10 IAP creation + pricing | Yes |
| §11 Submission | Yes |
| §12 Gate flip decision | Yes (code flip itself is one line) |
