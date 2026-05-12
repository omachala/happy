---
name: test-flight
description: >-
  Build the happy iOS app and upload to TestFlight via manual xcodebuild pipeline.
  Use when user says "deploy to TestFlight", "TestFlight", "upload build",
  "new TestFlight build", "TF build", "deploy TF", or asks to ship a TestFlight release.
argument-hint: "[build number]"
---

# TestFlight — happy iOS build & deploy

Personal-fork TestFlight pipeline. No EAS / Expo account. Runs locally on Boba.
Authoritative reference: `BUILD.md` at repo root.

## Pre-flight checks

1. **Detect platform** — `uname -s`. Must be **Darwin** with Xcode. Abort otherwise.
2. **Check working tree** — `git status`. If dirty, ask the user before continuing; the build encodes whatever's on disk after prebuild regenerates `ios/`.
3. **Branch** — happy fork pushes directly to `main` (see global memory `push_to_main.md`). Confirm the branch you're on is the one you want to ship.
4. **Build number** — read current `buildNumber` in `packages/happy-app/app.config.js`. New value is current + 1, or whatever the user passed as argument. iOS rejects duplicate `(version, buildNumber)` pairs.

## Process

### 1. Bump build number

Edit `packages/happy-app/app.config.js`:

```js
ios: {
    bundleIdentifier: bundleId,
    buildNumber: "<N>",  // ← increment
```

If you also bumped `version` in the same file, build number can reset to `"1"`.

### 2. Install + typecheck (repo root)

```bash
cd /Users/ondrej/projects/happy
pnpm install
pnpm --filter happy-app typecheck
```

Fix any type errors before continuing — they will not surface again in the archive step.

### 3. Prebuild — regenerate `ios/`

```bash
cd /Users/ondrej/projects/happy/packages/happy-app
APP_ENV=production pnpm prebuild --platform ios --no-install
```

`pnpm prebuild` does `rm -rf ios android` first, then re-runs `expo prebuild`. Anything you hand-edit inside `ios/` is lost on every build. The one file we keep across prebuilds is `packages/happy-app/deploy/ExportOptions.plist` — it lives outside `ios/` for exactly this reason. Don't move it.

### 4. CocoaPods (~1–2 min)

```bash
cd /Users/ondrej/projects/happy/packages/happy-app/ios
LANG=en_US.UTF-8 pod install
```

`LANG=en_US.UTF-8` avoids a Ruby string-encoding crash on some macOS locales.

### 5. Archive (~10–15 min, run in foreground)

```bash
cd /Users/ondrej/projects/happy/packages/happy-app/ios
rm -rf build/Happy.xcarchive
xcodebuild archive \
  -workspace Happy.xcworkspace \
  -scheme Happy \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath build/Happy.xcarchive \
  -allowProvisioningUpdates \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_T43ZQ8KTCH.p8 \
  -authenticationKeyID T43ZQ8KTCH \
  -authenticationKeyIssuerID "$(cat ~/.appstoreconnect/issuer-id)" \
  DEVELOPMENT_TEAM=924FH7MYCN \
  CODE_SIGN_STYLE=Automatic
```

**Run in foreground** (not `run_in_background`) — the user wants to watch progress live. Use `timeout: 1800000` (30 min) on the Bash tool call. Wait for `** ARCHIVE SUCCEEDED **`.

### 6. Export + upload (single step)

`packages/happy-app/deploy/ExportOptions.plist` has `destination=upload`, so this one command exports and uploads to App Store Connect — no separate altool / Transporter step.

```bash
cd /Users/ondrej/projects/happy/packages/happy-app/ios
xcodebuild -exportArchive \
  -archivePath build/Happy.xcarchive \
  -exportPath build/ipa \
  -exportOptionsPlist ../deploy/ExportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_T43ZQ8KTCH.p8 \
  -authenticationKeyID T43ZQ8KTCH \
  -authenticationKeyIssuerID "$(cat ~/.appstoreconnect/issuer-id)"
```

**Run in foreground** (not `run_in_background`) so the upload progress is visible. Use `timeout: 1800000` (30 min). Success signals (both must appear):
- `Progress 100%: Upload succeeded.`
- `** EXPORT SUCCEEDED **`

A non-zero exit is usually just dSYM warnings on prebuilt frameworks (React, LiveKit, ffmpeg, Hermes). Harmless — verify the two lines above before reporting failure.

### 7. Commit + push to main

Per project memory, happy fork pushes directly to `main`:

```bash
git add packages/happy-app/app.config.js
git commit -m "chore: bump iOS buildNumber to <N> for TestFlight"
git checkout main
git merge --ff-only personal-build  # if work was done on personal-build
git push origin main
```

If `personal-build` is also a tracked branch (it is on the omachala/happy fork), keep it in sync:

```bash
git push origin personal-build
```

No tags — this fork doesn't use the `testflight-vN` tagging scheme that diction uses (single-developer, short-lived TestFlight cycles).

### 8. Confirm

Tell the user:
- New build number
- Upload status (succeeded / failed; quote the success lines)
- Reminder: build appears in App Store Connect → TestFlight tab within seconds, then 5–45 min processing before it's "Ready to Test"
- Internal testers (already in the group) get it automatically

### 9. What to test

Show the user the user-facing diff for the new build:

```bash
# Find previous build's commit (the buildNumber bump commit before this one)
git log --oneline -- packages/happy-app/app.config.js | head -5
```

Pick the prior bump commit, then:

```bash
git log <prev-bump>..HEAD --oneline --no-merges
```

Translate commit subjects to plain-English testing instructions. Skip pure version-bump commits.

## Credentials

| Item | Location |
|------|----------|
| ASC API key (.p8) | `~/.appstoreconnect/private_keys/AuthKey_T43ZQ8KTCH.p8` |
| Key ID | `T43ZQ8KTCH` |
| Issuer ID | `~/.appstoreconnect/issuer-id` (chmod 600) |
| Apple Developer Team | `924FH7MYCN` ("Ondrej Machala") |
| Bundle ID | `com.omachala.happy` |
| ASC App ID | `6768410446` (Happy Localhost) |

Sensitive files for this project live in `.claude/local/` and `.claude/secrets/` (both gitignored).

## Common gotchas

| Problem | Fix |
| --- | --- |
| `No Accounts: Add a new account in Accounts settings.` | The `-authenticationKey*` flags are missing or wrong. Don't try to log into Xcode UI — Boba runs headless. |
| `No profiles for 'com.omachala.happy' were found` | `-allowProvisioningUpdates` should auto-create. If not, manually register the App ID at the Apple Developer Portal. |
| `No app record found` | App Store Connect entry for `com.omachala.happy` doesn't exist. Create at App Store Connect → Apps → +. |
| `Bundle version must be higher than previously uploaded` | Step 1 was skipped or wasn't saved. Bump `buildNumber` in `app.config.js`. |
| dSYM warnings on React/LiveKit/Hermes/ffmpeg frameworks | Harmless. Those ship without debug symbols. Your own code still symbolicates. |
| `pnpm prebuild` removed something you hand-edited | Move it outside `ios/` (see `deploy/ExportOptions.plist` for the pattern), or add it to an Expo config plugin. |

## Rules

- Never deploy without explicit user permission
- Always typecheck before prebuild — caught here, not after a 15-minute archive
- Always run prebuild before pod install before archive — they are sequential, not idempotent
- Build numbers must be strictly increasing and unique per `(version, buildNumber)` pair
- Run the archive and export/upload steps in the foreground (do **not** pass `run_in_background`) — the user wants to watch progress live; use `timeout: 1800000` on those Bash calls
- Push to `main` directly per project convention; do not open PRs on this fork
