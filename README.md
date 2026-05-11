# Happy — Personal Fork

This is **[omachala/happy](https://github.com/omachala/happy)**, a personal fork of [slopus/happy](https://github.com/slopus/happy) — a mobile + web + CLI client for Claude Code.

## Why this fork

I love Happy but want my own simpler, more opinionated build:

- **Strip telemetry & monetization.** No PostHog analytics, no RevenueCat paywalls, no Firebase Android FCM (slopus's account anyway).
- **Strip the inbox feature.** Personal device, no social layer needed.
- **Simpler navigation.** No bottom tab bar — just the sessions list. Tap the logo to reach settings.
- **Self-hosted server.** Server defaults to my own `happy.macha.la` instance (already self-hosted; see `~/network/HAPPY.md` on Din).
- **Own TestFlight builds.** Bundle `com.omachala.happy`, signed under my Apple Developer team, distributed only to me.

The upstream `slopus/happy` project is great and actively developed — I want to keep pulling their improvements while keeping my personal customizations on top.

## Architecture

```
iOS app (TestFlight build of com.omachala.happy)
    │
    ▼ end-to-end encrypted over WebSocket / HTTPS
happy.macha.la (self-hosted Caddy → happy-server on Din)
    │
    ├── Postgres
    ├── Redis
    └── MinIO

CLI on Boba/Din ──── happy auth login ──── pairs to the iOS app
```

The iOS app is the master device (holds the master secret). Each CLI machine (Boba, Din) authenticates by scanning a URL from the iOS app.

## Keeping in sync with upstream

```bash
git fetch upstream
git checkout personal-build
git merge upstream/main
# expect conflicts in:
#   app.config.js, eas.json, package.json
#   sources/components/MainView.tsx, HeaderLogo.tsx
#   sources/track/tracking.ts, sources/sync/revenueCat/*
#   sources/sync/appConfig.ts, sources/sync/serverConfig.ts
#   sources/app/_layout.tsx (PostHog import removed)
# resolve, then:
pnpm install
pnpm --filter happy-app typecheck
```

After resolving, follow `BUILD.md` to ship a new TestFlight build.

## Build & deploy

See **[BUILD.md](./BUILD.md)** for the full TestFlight workflow (prebuild → pod install → archive → upload to App Store Connect).

## Upstream

To see what's diverged from `slopus/happy`:

```bash
git log --oneline upstream/main..personal-build
```
