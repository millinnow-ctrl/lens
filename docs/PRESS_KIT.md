# LensMood — Press Kit

Working press kit for the SwiftUI app in `LensMoodApp/` (bundle id
`app.lensmood.ios`). Created 2026-07-18 by council ruling. Send date is
day 8 of the launch schedule (`docs/LAUNCH_RUNBOOK.md` §13); the send
itself is the owner's decision. Every asset below carries a §16 honesty
status — nothing ships with a claim its render can't back.

---

## 1. The one sentence

> **"Filters guess. LensMood measures the light in your photo and
> develops it the way film actually would."**

This is the ratified differentiation sentence
(`docs/MARKET_RESEARCH.md`, 2026-07-17 round). Every pitch, every
caption, every nomination paragraph is a variation of it — never a
replacement for it.

## 2. The angle menu (pick per outlet)

One story, three doors. Match the door to the outlet; never send the
same email twice.

| Angle | The pitch in one line | Best-fit outlets |
|---|---|---|
| **Craft / indie** | Solo developer, pure SwiftUI, on-device light physics — 18 film cameras argued from physical behavior, not presets. | MacStories, Daring-Fireball-sphere blogs, indie-dev newsletters |
| **Privacy** | The camera app that refuses the cloud — App Privacy label reads **Data Not Collected**; every develop works in airplane mode. | 9to5Mac, privacy-focused newsletters and podcasts |
| **The refusal** | No generative anything — the photograph is never invented, only developed. Deterministic, re-derivable renders. | PetaPixel, photography press wary of synthetic imagery |

Community: honest show-and-tell in **r/iphoneography** (the developer
posting as the developer, work shown plainly). Explicitly excluded:
**r/AnalogCommunity** [believed: simulation apps read as provocation
there — same ruling as `docs/GROWTH_PLAYBOOK.md` §5].

## 3. The demo that carries it

Two demos, in this order:

1. **The airplane-mode develop.** Airplane mode on, pick a photo,
   full develop, save. No spinner, no login, nothing to time out. This
   is the privacy claim made physical.
2. **The light test.** One camera, two lights: the same camera develops
   a noon photo and a night photo *differently*, decision notes visible
   on screen. **Every pitch leads with a two-light pair, not a single
   before/after** — a single photo cannot prove adaptivity; only a pair
   can.

## 4. Asset inventory with §16 status

### Ships as-is

| Asset | Honesty status |
|---|---|
| UI captures (home shelf, capture, develop, library, Print, Tape) | Real screens; no engine-behavior claim made, none needed. |
| Light Test pair exports from `ui-artifacts/share-cards/` | Device-honest engine output rendered at CI settings — it **understates** device results, and outreach copy should say so plainly ("renders shown at conservative settings"). |

### BLOCKED until the device re-capture (`docs/LAUNCH_RUNBOOK.md` §8, item 2)

| Asset | Why blocked |
|---|---|
| The depth-parallax video | Claims mask-driven behavior; simulator mattes are empty [measured: ci-captures ad-material run, max pixel 3/255]. Shipping the claim from simulator renders is belief dressed as fact. |
| Any rim-light / skin-protection / sky caption | Same reason — every mask-behavior claim must be built from real device mattes. |

The block clears the moment the §8 ad-material re-capture runs on a
physical device. Until then these assets do not leave the repo.

## 5. Featuring nomination (ready to paste)

Submit at day −2 per `docs/LAUNCH_RUNBOOK.md` §13 (App Store Connect →
Featuring nomination). Draft:

> LensMood is built by a solo developer: 18 film cameras, each argued
> from the physical behavior of a real camera era rather than a preset.
> The app reads each photograph's light on-device and develops
> accordingly — the same camera renders a noon photo and a night photo
> differently, and shows its reasoning as decision notes. It is pure
> SwiftUI on Core Image, Metal, and Vision; its App Privacy label is
> Data Not Collected — no account, no upload, fully functional offline.
> A one-time purchase is available alongside a yearly plan; import and
> full-resolution export are free forever.

(The technology never names itself — the paragraph stays free of the
banned vocabulary by design, matching the app's own copy hygiene.)

## 6. Boilerplate + contact (owner fills placeholders)

**Boilerplate (short):**

> LensMood turns any photo into a shot from a real camera era. 18 film
> cameras, developed on-device — nothing uploaded, ever. Built by
> [OWNER-NAME] as an independent app. Free with six full cameras;
> one-time purchase available.

**Fact box:**

- App: LensMood — Film Camera (iOS, iPhone, free download)
- Availability: App Store, [LAUNCH-DATE — owner decides]
- Price: free; LensMood Plus $19.99/yr or $49.99 lifetime
  [RECOMMENDATION — final points are the owner's, set in App Store
  Connect]
- Privacy: Data Not Collected; works offline
- Press contact: [OWNER-NAME], [OWNER-EMAIL]
- Press assets: [HOSTED-URL for the shipping asset set from §4]
- Promo codes: available on request (App Store promo codes, 28-day
  expiry)
