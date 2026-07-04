# LensMood — App Store readiness checklist

Audit of everything Apple requires (App Review Guidelines + HIG), what's
already in place, and what still needs the user's action. Updated July 2026.

## Payments — guideline 3.1.1 (the big one)

| Item | Status |
|---|---|
| Digital subscriptions must use Apple In-App Purchase on iOS | ✅ Architected: `src/lib/purchases.ts` is the platform seam. On native iOS the demo web checkout is disabled and purchases route to a StoreKit bridge; on web, the demo checkout remains. |
| No link-outs to external payment from the iOS app | ✅ Pricing page shows "Billed through your Apple ID" on native, no external checkout links. |
| Restore Purchases affordance | ✅ Visible on the pricing screen on native builds. |
| Product IDs | Defined: `app.lensmood.ios.{creator,pro,studio}.monthly` — **you must create these in App Store Connect** (auto-renewable, one subscription group). |
| StoreKit bridge | ⚠️ Stubbed. Before release, add RevenueCat (`@revenuecat/purchases-capacitor`) or `@squareetlabs/capacitor-subscriptions` and expose it as `window.LensMoodIAP { purchase, restore }`, or replace the seam calls directly. Requires a Mac-less path: config is all JS; the plugin adds via npm + `npx cap sync`. |
| Price display | Fetch localized prices from StoreKit at runtime for the native pricing screen (App Review flags hard-coded USD). The seam is ready for it. |

## Sign in — guideline 4.8

- ✅ "Continue with Apple" is offered first and most prominently wherever Google sign-in appears (HIG placement).
- ⚠️ Demo only: before release wire `@capacitor-community/apple-sign-in` and a real Google OAuth client; keep Apple's email-relay support (privacy page already promises it).

## Account deletion — guideline 5.1.1(v)

- ✅ "Delete account & data" in the account sheet wipes all local data with confirmation. (All data is local, so deletion is genuinely complete.)

## Privacy

| Item | Status |
|---|---|
| Privacy policy URL (required in App Store Connect) | ✅ `/privacy` page shipped; use `https://<your-domain>/privacy`. |
| Terms of use URL (required for auto-renewable subs) | ✅ `/terms` page shipped. |
| App Privacy "nutrition label" answers | Data not collected — photos processed on-device, no analytics, no tracking. Answer "Data Not Collected" unless you add accounts/sync later. |
| ATT (App Tracking Transparency) | Not needed — no tracking. Do not add the prompt. |
| Permission strings | ✅ Camera, Photo Library (read + add), Microphone strings in `Info.plist`, each explains the actual use. |

## Binary & assets

- ✅ App icon 1024 (`AppIcon-512@2x.png`, regenerate at 1024 naming if ASC complains), adaptive PWA icons, splash via Capacitor.
- ✅ `ITSAppUsesNonExemptEncryption=false` (skips export-compliance questions).
- ✅ Portrait-first mobile UI, safe-area insets respected, haptics via Capacitor.
- ✅ Reduced-motion honored (hero video and 3D deck fall back).
- CI: `.github/workflows/testflight.yml` builds and uploads on tag push once the four ASC secrets are set.

## Content risks — guideline 5.2 (intellectual property) ⚠️ ACTION NEEDED

Style names reference real brands: **GQ Editorial, A24 Movie Still, Leica
Street, Polaroid, Kodachrome, Lomo, Blockbuster, iPhone Flash, Super 8**.
App Review and rights holders can (and do) flag this. Recommended rename map
kept in one place (`src/lib/styles.ts` names only — engine ids can stay):

- iPhone Flash → Phone Flash · GQ Editorial → Magazine Editorial · A24 Movie
  Still → Indie Film Still · Leica Street → Classic Street · Polaroid →
  Instant Film · Kodachrome → 60s Slide Film · Lomo → Toy Camera ·
  Blockbuster → Summer Movie · Super 8 → Home Movie 8mm

The Terms page already carries a non-affiliation disclaimer, but renaming
before submission is the safe call. **Waiting on your go-ahead.**

## Guideline 2.1 — completeness

- ✅ No dead links (placeholder social links removed), no "demo" copy on
  the native purchase path, all features work offline after install.
- Demo sign-in is acceptable for TestFlight; App Store release needs the
  real auth above.

## Website (App Store marketing URL)

- ✅ OG/Twitter cards + 1200×630 `og.jpg`, new-brand favicon, theme-color,
  descriptive title/meta, `/privacy` + `/terms` in the footer, PWA manifest
  and offline support.

## Submission-day inputs only you can provide

1. Apple Developer Program membership + the 4 GitHub secrets
   (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_API_KEY_P8`, `APPLE_TEAM_ID`) — then
   push tag `v1.0.0` to trigger the TestFlight workflow.
2. App Store Connect: create the app, the three subscription products, and
   paste the privacy/terms URLs.
3. Decide on the style-name rename map above.
4. Support URL + marketing URL (any page on your domain works).
