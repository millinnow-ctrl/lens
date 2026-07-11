# Ship LensMood to TestFlight (EAS)

LensMood is a native **Expo (React Native + Skia)** app in `lensmood-native/`.
Builds run on **EAS** (Expo's cloud) — no Mac required.

## One-time setup

```bash
cd lensmood-native
npm install
npm i -g eas-cli
eas login                 # sign in to your Expo account (free to create)
eas init                  # links this project → writes extra.eas.projectId into app.json
```

Then connect your Apple account so EAS can build + submit:

```bash
eas credentials           # follow prompts for iOS (App Store Connect API key)
```

You'll need an **App Store Connect API key** (App Store Connect → Users and
Access → Integrations → App Store Connect API → generate a key). EAS stores it
securely; you don't handle certificates or provisioning profiles by hand.

## Build + submit a beta

From `lensmood-native/`:

```bash
eas build --platform ios --profile production --auto-submit
```

That builds on EAS and uploads straight to TestFlight. When it finishes, the
build appears in App Store Connect → your app → TestFlight (allow a few minutes
for Apple to finish processing before it's installable).

## No terminal? Use GitHub Actions

The repo's **TestFlight** workflow (`.github/workflows/testflight.yml`) runs the
same command on push of a `v*` tag or from the Actions tab (Run workflow).

Required repository secret (Settings → Secrets and variables → Actions):

| Secret | Where to get it |
| --- | --- |
| `EXPO_TOKEN` | expo.dev → Account settings → Access tokens → Create token |

The Apple submit credentials are the ones you set with `eas credentials` above —
EAS reads them from your Expo project, so the workflow needs no Apple secrets.

## Bump the version

`app.json` → `expo.version` is the marketing version (e.g. `1.0.1`). The build
number auto-increments (`eas.json` production profile has `autoIncrement: true`).
