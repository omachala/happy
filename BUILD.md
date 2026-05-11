# Build & Deploy to TestFlight

This is the **manual local build pipeline** for shipping a new TestFlight build of this fork. No EAS / Expo account required.

Everything runs on **Boba** (the MacBook in the garage lab).

## Prerequisites (one-time)

- **Xcode** with command-line tools.
- **Node 22+** with `pnpm` enabled via `corepack enable pnpm`.
- **CocoaPods** (`brew install cocoapods` or installed by Xcode).
- **Apple Developer Program** membership (paid), team ID `924FH7MYCN`.
- **App Store Connect API key** at `~/.appstoreconnect/private_keys/AuthKey_T43ZQ8KTCH.p8`. Key ID `T43ZQ8KTCH`. Issuer ID is in App Store Connect → Users and Access → Integrations → Keys (top of page).
- **App Store Connect app entry** for bundle `com.omachala.happy` already created (one-time, done via the ASC web UI).
- **Distribution certificate** `iPhone Distribution: Ondrej Machala (924FH7MYCN)` in the macOS keychain.

## Bump build number

iOS rejects duplicate `(version, buildNumber)` pairs in TestFlight. Before every build, **bump `buildNumber` in `packages/happy-app/app.config.js`**:

```js
ios: {
    bundleIdentifier: bundleId,
    buildNumber: "3",  // ← increment
```

If you also bumped the app version (`version: "1.7.0"` in the same file), build number can reset to `"1"`.

## Build steps

All paths below are relative to repo root.

```bash
# 1. Make sure deps are installed and clean
cd ~/projects/happy
pnpm install
pnpm --filter happy-app typecheck

# 2. Generate native iOS project from Expo config (overwrites ios/)
cd packages/happy-app
APP_ENV=production pnpm prebuild --platform ios --no-install

# 3. Install CocoaPods native deps (~2–3 min)
cd ios
LANG=en_US.UTF-8 pod install

# 4. Archive (Release, signed with team 924FH7MYCN, ~10–15 min)
rm -rf build/Happy.xcarchive
xcodebuild archive \
  -workspace Happy.xcworkspace \
  -scheme Happy \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath build/Happy.xcarchive \
  -allowProvisioningUpdates \
  -authenticationKeyPath /Users/ondrej/.appstoreconnect/private_keys/AuthKey_T43ZQ8KTCH.p8 \
  -authenticationKeyID T43ZQ8KTCH \
  -authenticationKeyIssuerID <ISSUER_ID_UUID> \
  DEVELOPMENT_TEAM=924FH7MYCN \
  CODE_SIGN_STYLE=Automatic

# 5. Export + upload to TestFlight in one shot
#    ExportOptions.plist has destination=upload, so xcodebuild uploads
#    directly to App Store Connect — no separate altool/Transporter step.
xcodebuild -exportArchive \
  -archivePath build/Happy.xcarchive \
  -exportPath build/ipa \
  -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath /Users/ondrej/.appstoreconnect/private_keys/AuthKey_T43ZQ8KTCH.p8 \
  -authenticationKeyID T43ZQ8KTCH \
  -authenticationKeyIssuerID <ISSUER_ID_UUID>
```

Replace `<ISSUER_ID_UUID>` with the actual UUID from App Store Connect.

A non-zero exit on step 5 is usually just dSYM warnings — check the output for `Upload succeeded.` Look for the line `Progress 100%: Upload succeeded.` followed by `** EXPORT SUCCEEDED **`.

## After upload

1. Open **App Store Connect → TestFlight tab**. Build appears under "Processing" within seconds.
2. Wait 5–45 min for Apple processing.
3. Once processing finishes, the build moves to "Ready to Test" (export compliance is already declared in `app.config.js` via `usesNonExemptEncryption: false`, so no manual compliance prompt).
4. Build is auto-available to existing TestFlight testers (Internal group). No additional action needed if you're already in the group.

## Querying build status without the web UI

To check processing status from the CLI, use the ASC API:

```bash
node scripts/asc-build-status.mjs   # (if you make one)
```

…or paste this one-shot into a `node -` REPL using the key + issuer above. The endpoint is `/v1/builds?filter[app]=<appId>&sort=-uploadedDate`.

The `Happy Localhost` app ID is **6768410446**.

## What's actually happening

- `expo prebuild` generates the iOS Xcode project from `app.config.js` + plugins. It overwrites the `ios/` directory each run.
- `pod install` resolves native dependencies (LiveKit WebRTC, Hermes, libsodium, Skia, etc. — ~180 pods).
- `xcodebuild archive` compiles + links + signs the app into a `.xcarchive`.
- `xcodebuild -exportArchive` with `destination=upload` in `ExportOptions.plist` skips writing an IPA to disk and uploads straight to App Store Connect.

## Common gotchas

| Problem | Fix |
| --- | --- |
| Archive fails: "No Accounts: Add a new account in Accounts settings." | Use `-authenticationKey*` flags with the ASC API key (this doc's commands already do). Don't try to use Xcode UI on Boba — it's headless with lid closed. |
| Archive fails: "No profiles for 'com.omachala.happy' were found" | `-allowProvisioningUpdates` should auto-create the profile when API-key auth is provided. If it doesn't, manually register the App ID in the [Apple Developer Portal](https://developer.apple.com/account/resources/identifiers/list). |
| Upload error: "No app record found" | The App Store Connect app entry for `com.omachala.happy` doesn't exist. Create it at [App Store Connect → Apps → +](https://appstoreconnect.apple.com/apps). |
| Upload error: "Bundle version must be higher than previously uploaded" | Increment `buildNumber` in `app.config.js`. |
| dSYM warnings on prebuilt frameworks (React.framework, LiveKit, ffmpeg, Hermes) | Harmless. Those frameworks ship without debug symbols. Crashes in your own code still symbolicate. |

## Future automation

A `scripts/release-ios.sh` script could wrap steps 2–5 with the issuer ID pulled from `~/.appstoreconnect/issuer-id` (gitignored), and auto-bump `buildNumber` based on git commit count or timestamp. Not done yet — current process is manual.
