# Getting LensMood onto TestFlight

TestFlight is Apple's beta-distribution system: you upload a build once, and up to
10,000 people can install it on their iPhones through the TestFlight app — no cables,
no App Store review for internal testers.

## What you need first (both paths)

1. **An Apple Developer Program membership** — enroll at
   [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll).
   $99/year, personal or company. Approval is usually same-day.
2. **Your Team ID** — after enrolling, it's at
   [developer.apple.com/account](https://developer.apple.com/account) → Membership
   details. A 10-character code like `A1B2C3D4E5`.
3. **A registered App ID (bundle identifier)** — go to
   [developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers)
   → **+** → *App IDs* → *App* → set the Bundle ID to **`app.lensmood.ios`**
   (explicit, not wildcard). Capabilities: none needed. (If you'd rather use your own
   reverse-domain ID, change `appId` in `capacitor.config.ts` **and** the Bundle
   Identifier in Xcode/project settings to match, then use that everywhere below.)
4. **An app record in App Store Connect** — at
   [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → My Apps → **+** →
   *New App*. Platform iOS, name **LensMood** (or a variant if taken), primary language,
   the bundle ID from step 3, and any SKU string (e.g. `lensmood-001`).

Now pick a path:

---

## Path A — you have a Mac with Xcode (10 minutes)

```bash
git clone <this repo> && cd lens
npm install
npm run build
npx cap sync ios
npx cap open ios
```

Then in Xcode:

1. Click the **App** project in the sidebar → *Signing & Capabilities* tab →
   set **Team** to your team. Leave "Automatically manage signing" on.
2. At the top, change the run destination from a simulator to **Any iOS Device (arm64)**.
3. Menu **Product → Archive**. Wait for the build.
4. In the Organizer window that opens: **Distribute App → TestFlight & App Store →
   Upload**, accept the defaults, Upload.
5. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → your app →
   **TestFlight** tab. The build appears after ~10–30 min of processing.

Skip to **Inviting testers** below.

---

## Path B — no Mac: GitHub Actions does it (one-time ~15 min setup)

The repo ships `.github/workflows/testflight.yml`, which builds the app on a cloud Mac
and uploads it to TestFlight. It uses Apple's **cloud-managed signing**, so you never
create certificates or provisioning profiles. You only need to add four secrets.

### 1. Create an App Store Connect API key

App Store Connect → **Users and Access** → **Integrations** tab → *App Store Connect
API* → *Team Keys* → **+**.

- Name: `github-actions`
- Access: **App Manager**

Download the `AuthKey_XXXXXXXXXX.p8` file (you can only download it once — keep it
safe). Note the **Key ID** shown in the row and the **Issuer ID** shown at the top of
the page.

### 2. Add the four repository secrets

GitHub repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
| --- | --- |
| `ASC_KEY_ID` | the Key ID, e.g. `2X9R4HXF34` |
| `ASC_ISSUER_ID` | the Issuer ID (a UUID) |
| `ASC_API_KEY_P8` | the *entire text contents* of the `.p8` file, including the `BEGIN`/`END` lines |
| `APPLE_TEAM_ID` | your 10-character Team ID |

### 3. Run it

GitHub repo → **Actions** tab → **TestFlight** workflow → **Run workflow**.

~15 minutes later the build is uploaded; Apple then processes it for another
~10–30 minutes before it appears in App Store Connect → TestFlight. Every run
auto-increments the build number (it uses the workflow run number), so you can ship
repeatedly without touching version fields. Pushing a git tag like `v1.0.1` also
triggers a build.

> First-run hiccups worth knowing:
> - *"No profiles / app record found"* → step 3 or 4 of the prerequisites was skipped,
>   or the bundle ID doesn't match.
> - *Key permission errors* → the API key must be **App Manager**, not Developer.

---

## Inviting testers

In App Store Connect → your app → **TestFlight** tab:

- **Internal testers** (up to 100, instant, no review): add people to your team under
  *Users and Access* first, then add them to an internal group. Builds are available
  the moment processing finishes.
- **External testers** (up to 10,000): create an external group → add emails **or**
  enable a **public link** you can drop in a bio or group chat. The *first* build for
  external testers goes through a light Beta App Review (usually < 24 h). You'll also
  fill in a short "What to Test" note per build.

Testers install the **TestFlight** app from the App Store, tap your invite link, and
LensMood installs with a little orange dot. Builds expire after 90 days — just ship a
new one.

## When you're ready for the real App Store

Same builds, same pipeline. In App Store Connect fill in the App Store listing
(screenshots, description, privacy details — LensMood processes photos on-device and
sends nothing anywhere, which makes the privacy questionnaire short), pick a build,
and **Submit for Review**.
