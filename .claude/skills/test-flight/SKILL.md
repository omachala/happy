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
5. **Keychain health** — `security find-identity -v -p codesigning /Library/Keychains/System.keychain`. **Must show both** `Apple Development: Created via API (T43ZQ8KTCH)` and `Apple Distribution: Ondrej Machala (924FH7MYCN)`. If either is missing — especially after a Boba reboot — run the [Keychain recovery](#keychain-recovery-after-reboot) procedure BEFORE attempting any of the build steps. Skipping this turns a 20-minute build into a 1-hour debugging session.

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
| `errSecInternalComponent` from codesign on a framework | Keychain state broke — usually after a Boba reboot. Run [Keychain recovery](#keychain-recovery-after-reboot). Do not try to "just retry" or revoke certs via Xcode UI. |
| `Revoke certificate: …private key is not installed in your keychain` | Same root cause. Run [Keychain recovery](#keychain-recovery-after-reboot). |
| `Certificate installation failed: Write permissions error` | Same — Xcode can't write into the headless-session keychain. Run [Keychain recovery](#keychain-recovery-after-reboot). |
| `Warning: unable to build chain to self-signed root for signer` | Missing intermediate. Apple Root CA + WWDR-G3 must live in `/Library/Keychains/System.keychain` (not just `SystemRootCertificates.keychain`). The recovery procedure adds them. |

## Keychain recovery after reboot

**Why this exists.** Boba is headless (lid closed, garage). When it reboots, no GUI login happens — only SSH sessions. macOS's keychain agent doesn't fully initialize the user-domain keychain context in SSH sessions, so:

- `security find-identity` in the SSH session reports **0 valid identities** even though certs exist on disk
- `xcodebuild` with `-allowProvisioningUpdates` + API key tries to recreate certs, fails to install them (`Write permissions error`), and leaves orphans on Apple's portal
- `codesign` cannot use private keys (`errSecInternalComponent`)
- The cert chain can't be assembled because Apple Root CA + WWDR are only in `SystemRootCertificates.keychain`, which `codesign` doesn't consult

The fix is to import the cert+key pairs into `/Library/Keychains/System.keychain` (root-owned, session-independent) **and** copy the chain certs in alongside them. Once done, this survives reboots and the regular build flow works from any SSH session.

### Prereqs

- User's login password (Boba account `ondrej`). You will need it for `sudo` and for keychain `-k <password>` flags.
- `fastlane` installed: `which fastlane` should return `/usr/local/bin/fastlane`. (`brew install fastlane` if missing.)
- `python3` with `pyjwt` and `cryptography`: `python3 -c "import jwt"` should succeed. (`pip3 install pyjwt cryptography` if missing.)
- `jq` installed: `which jq`. (`brew install jq` if missing.)

### Step A — assess

```bash
security find-identity -v -p codesigning /Library/Keychains/System.keychain
```

If both `Apple Development: Created via API (T43ZQ8KTCH)` and `Apple Distribution: Ondrej Machala (924FH7MYCN)` are present, **stop — recovery is unnecessary, the build should work as-is**. Proceed to the regular pipeline.

Otherwise continue.

### Step B — build a JWT for the App Store Connect API

```bash
cat > /tmp/asc_jwt.py <<'PYEOF'
import jwt, time
KEY_ID = "T43ZQ8KTCH"
ISSUER_ID = open("/Users/ondrej/.appstoreconnect/issuer-id").read().strip()
KEY = open("/Users/ondrej/.appstoreconnect/private_keys/AuthKey_T43ZQ8KTCH.p8").read()
print(jwt.encode(
    {"iss": ISSUER_ID, "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
    KEY, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"},
))
PYEOF
TOKEN=$(python3 /tmp/asc_jwt.py)
```

### Step C — revoke orphan certs on Apple's side

List what exists:

```bash
curl -s -H "Authorization: Bearer $TOKEN" "https://api.appstoreconnect.apple.com/v1/certificates?limit=200" \
  | jq '.data[] | {id, type: .attributes.certificateType, name: .attributes.name, serialNumber: .attributes.serialNumber}'
```

Any `DEVELOPMENT` named `Apple Development: Created via API` and any `DISTRIBUTION` named `Apple Distribution: Ondrej Machala` are orphans (we have no private key for them locally — they were tied to keychain entries that pre-dated the reboot). Revoke each:

```bash
curl -s -X DELETE -H "Authorization: Bearer $TOKEN" \
  "https://api.appstoreconnect.apple.com/v1/certificates/<cert-id>"
```

Expected response: `204 No Content`. Leave the `Apple Development: Ondrej Machala` cert alone if present — it's tied to the personal Apple ID, harmless.

### Step D — build a fastlane API-key file

```bash
ISSUER=$(cat ~/.appstoreconnect/issuer-id)
python3 - <<PYEOF
import json, pathlib
p8 = pathlib.Path('/Users/ondrej/.appstoreconnect/private_keys/AuthKey_T43ZQ8KTCH.p8').read_text()
json.dump({
    "key_id": "T43ZQ8KTCH",
    "issuer_id": "$ISSUER",
    "key": p8,
    "duration": 1200,
    "in_house": False,
    "is_key_content_base64": False,
}, open('/tmp/asc_key.json', 'w'))
PYEOF
chmod 600 /tmp/asc_key.json
```

### Step E — generate fresh dev + distribution cert pairs

```bash
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
security unlock-keychain -p '<login-password>' ~/Library/Keychains/login.keychain-db
mkdir -p /tmp/certs /tmp/certs-dist

# Development cert
fastlane cert \
  --api_key_path /tmp/asc_key.json \
  --output_path /tmp/certs \
  --keychain_path ~/Library/Keychains/login.keychain-db \
  --keychain_password '<login-password>' \
  --development true

# Distribution cert
fastlane cert \
  --api_key_path /tmp/asc_key.json \
  --output_path /tmp/certs-dist \
  --keychain_path ~/Library/Keychains/login.keychain-db \
  --keychain_password '<login-password>' \
  --development false
```

fastlane will say `Could not find the newly generated certificate installed` — **ignore it**, it's the same SSH-session keychain visibility issue. Verify the files exist:

```bash
ls /tmp/certs/        # <ID>.cer, <ID>.certSigningRequest, <ID>.p12 (MISLABELED — see step F)
ls /tmp/certs-dist/   # same shape
```

### Step F — pack them as real PKCS12 bundles

**fastlane's `.p12` file is actually a PEM-encoded RSA private key, not a PKCS12 bundle.** `file /tmp/certs/*.p12` will confirm `PEM RSA private key`. Repack as a real PKCS12 with the cert:

```bash
for d in /tmp/certs /tmp/certs-dist; do
  cer=$(ls $d/*.cer | head -1)
  key=$(ls $d/*.p12 | head -1)
  id=$(basename $cer .cer)
  openssl x509 -inform DER -in $cer -out $d/$id.crt.pem
  openssl pkcs12 -export -legacy \
    -inkey $key \
    -in $d/$id.crt.pem \
    -out $d/$id.real.p12 \
    -password pass:<login-password>
done
```

### Step G — import into System.keychain (the session-independent one)

```bash
sudo security import /tmp/certs/*.real.p12 \
  -k /Library/Keychains/System.keychain \
  -P '<login-password>' \
  -A -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/xcodebuild

sudo security import /tmp/certs-dist/*.real.p12 \
  -k /Library/Keychains/System.keychain \
  -P '<login-password>' \
  -A -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/xcodebuild

sudo security set-key-partition-list \
  -S apple-tool:,apple:,codesign:,unsigned: \
  -s -k '' \
  /Library/Keychains/System.keychain
```

### Step H — add Apple Root CA + WWDR-G3 to System.keychain

`codesign` builds its trust chain using `System.keychain` only, not `SystemRootCertificates.keychain`. The chain certs ship pre-installed in `login.keychain-db` and the system roots store, but **not** in `System.keychain`. Copy them over:

```bash
# Extract WWDR-G3 from the login keychain
security find-certificate -a -c "Apple Worldwide Developer Relations Certification Authority" \
  -p ~/Library/Keychains/login.keychain-db > /tmp/wwdr_all.pem
# Pick the G3 cert (issuer for "Apple Development: Created via API")
awk '/-----BEGIN/{c++} c==2 && /-----BEGIN/,/-----END/' /tmp/wwdr_all.pem > /tmp/wwdr_g3.pem
# Apple Root CA
security find-certificate -c "Apple Root CA" -p ~/Library/Keychains/login.keychain-db > /tmp/apple_root.pem

sudo security import /tmp/wwdr_g3.pem  -k /Library/Keychains/System.keychain -A
sudo security import /tmp/apple_root.pem -k /Library/Keychains/System.keychain -A
```

(If your dev cert is issued by a newer WWDR generation than G3, you'll need to pick the matching intermediate. Verify with `openssl x509 -inform DER -in /tmp/certs/*.cer -noout -issuer` — the issuer's `OU=G<N>` tells you which generation.)

### Step I — verify

```bash
security find-identity -v -p codesigning /Library/Keychains/System.keychain
# Must show:
#   Apple Development: Created via API (T43ZQ8KTCH)
#   Apple Distribution: Ondrej Machala (924FH7MYCN)
#   2 valid identities found
```

Sanity check by signing any framework manually:

```bash
DEV_HASH=$(security find-identity -v -p codesigning /Library/Keychains/System.keychain \
  | grep "Apple Development" | awk '{print $2}')
/usr/bin/codesign --force --sign "$DEV_HASH" -v /System/Applications/Calculator.app 2>&1 || true
# A "code object is not signed at all" / "signed bundle" line means codesign reached the key.
# errSecInternalComponent means the recovery is incomplete — recheck steps G + H.
```

Now proceed to the regular pipeline starting at step 2 (`pnpm install`). The build should succeed normally — every subsequent build will pick up the certs from `System.keychain` without further fuss.

### Cleanup

Leave the cert files in `/tmp/certs*` until the build succeeds. Once it's uploaded, you can `rm -rf /tmp/certs /tmp/certs-dist /tmp/asc_key.json /tmp/asc_jwt.py` — System.keychain has the durable copy.

## Rules

- Never deploy without explicit user permission
- Always typecheck before prebuild — caught here, not after a 15-minute archive
- Always run prebuild before pod install before archive — they are sequential, not idempotent
- Build numbers must be strictly increasing and unique per `(version, buildNumber)` pair
- Run the archive and export/upload steps in the foreground (do **not** pass `run_in_background`) — the user wants to watch progress live; use `timeout: 1800000` on those Bash calls
- Push to `main` directly per project convention; do not open PRs on this fork
