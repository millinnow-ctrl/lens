# LensMood — App Store readiness checklist

Status snapshot for the **SwiftUI app in `LensMoodApp/`** (bundle id
`app.lensmood.ios`). The step-by-step path to submission lives in
**`docs/LAUNCH_RUNBOOK.md`** — this file only records what is true in the
repo today. Updated July 2026. (Earlier versions of this file described
the pre-Swift web/Capacitor incarnation; that content is obsolete.)

## In the binary — done

| Item | Status |
|---|---|
| `ITSAppUsesNonExemptEncryption: false` on all three targets (app, share extension, widgets) | ✅ `LensMoodApp/project.yml` — export-compliance question answered in the binary |
| `CFBundleDisplayName` "LensMood" on the app target | ✅ `INFOPLIST_KEY_CFBundleDisplayName` |
| `UILaunchScreen: {}` (SwiftUI system launch screen) | ✅ explicit key in the app's Info.plist properties |
| Permission strings — camera, microphone, Photos **add-only** | ✅ calm copy on app + share extension; import uses the system photo picker, so no read permission exists anywhere |
| Portrait-only, iPhone-only | ✅ `TARGETED_DEVICE_FAMILY: 1`, portrait orientation key |
| 1024px app icon in the asset catalog | ✅ `Resources/Assets.xcassets/AppIcon.appiconset` |
| Privacy manifest (`PrivacyInfo.xcprivacy`) in all three targets | ✅ no tracking, no collection, UserDefaults CA92.1; required-reason audit recorded in the file (no file-timestamp/boot-time/disk-space APIs used) |
| Share extension activation rule | ✅ one image max — never `TRUEPREDICATE` |
| No App Groups / push / iCloud capabilities needed | ✅ widgets and extension are self-contained |

## Review-risk posture — done

| Item | Status |
|---|---|
| Paywall with placeholder prices reachable by a reviewer (2.1/3.1 risk) | ✅ closed — in **release** builds the Account "Preview the supporter offer" row renders only when real StoreKit products loaded; DEBUG builds always show it for design review (`AccountView.swift`) |
| Hard-coded USD on a live purchase path | ✅ real prices always come from `Product.displayPrice`; placeholders render only when no products exist, and that screen is then unreachable in release |
| Restore-purchases affordance | ✅ always present on the paywall |
| No dark patterns | ✅ per `docs/PROFIT_ENGINE.md` never-list (no urgency, no confirm-shaming, no weekly plans) |
| Brand-referencing look names (old 5.2 IP concern) | ✅ resolved — shipped display names are original (Direct Flash, Tape 94, Street 35, Editorial Strobe, Independent Still, Instant 600, Slide 64, Toy Color, Wet Plate, …); real-brand words survive only in internal ids, which never render |
| Account deletion (5.1.1(v)) | n/a — there are no accounts and no collected data |
| ATT prompt | Correctly absent — no tracking |

## Documents — done, need owner action to go live

| Item | Status |
|---|---|
| Privacy policy text | ✅ `docs/PRIVACY_POLICY.md` — owner must set contact email + host it publicly (GitHub Pages suffices); URL goes into App Store Connect |
| App Privacy questionnaire answers | ✅ spelled out in runbook §6 — **Data Not Collected** |
| Age rating answers | ✅ runbook §7 — all None → 4+ |
| Review notes text | ✅ runbook §11 — on-device processing, no account, Tape uses camera+mic |
| IAP definitions | ✅ ids + types + group in runbook §10 (`app.lensmood.ios.plus.yearly`, `app.lensmood.ios.plus.lifetime`), pricing bands in `docs/PROFIT_ENGINE.md` |

## Open items (owner-only, in runbook order)

1. Apple Developer Program enrollment (+ Small Business Program before
   any gate flip) — runbook §1–2.
2. Signing on a Mac with automatic signing — §3.
3. Host the privacy policy; set the effective date and contact email — §4.
4. Create the ASC app record; **subtitle decision**: `18 cameras.
   One-time purchase.` only if the lifetime IAP ships with v1, otherwise
   use a neutral subtitle until the gate flips — §5.
5. Archive/upload, TestFlight device pass — §8.
6. Screenshots (6.9" required set; five tabs + Develop) — §9.
7. Submission — §11. Gate flip much later — §12.
