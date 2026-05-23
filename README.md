# ClaudeUO

A self-hosted Ultima Online shard built on the open-source ModernUO server,
with first-class support for both ClassicUO (desktop) and MobileUO (iOS/Android)
clients. This repo is the deployable monorepo &mdash; submodules pull in upstream
sources cleanly, and a shard overlay layers our customizations on top without
forking.

## Layout

```
ClaudeUO/
├── server/              # submodule → modernuo/ModernUO (.NET 10, the game server)
├── client/              # submodule → ClassicUO/ClassicUO (reference; players install themselves)
├── mobile/              # submodule → VoxelBoy/MobileUO    (reference; published to app stores)
├── shard/               # OUR overlay on top of ModernUO
│   ├── ClaudeUO.Admin/        # localhost-only admin TCP socket plugin
│   └── Distribution-overlay/  # files merged into server/Distribution at build time
├── automation/          # restart scheduler + broadcast scripts (run on the host)
├── deploy/              # DigitalOcean Ubuntu 24.04 provisioning + systemd unit
├── docs/                # architecture, deploy, restart-automation notes
└── .github/workflows/   # CI + push-to-main → deploy + 6h restart countdown
```

## Quick links

- [Architecture](docs/ARCHITECTURE.md) &mdash; what runs where and how the pieces fit
- [Deploy guide](deploy/README.md) &mdash; provisioning a fresh DigitalOcean droplet
- [Restart automation](docs/RESTART_AUTOMATION.md) &mdash; broadcast schedule, manual ops

## Status / TODO

- [x] Submodules wired (ModernUO, ClassicUO, MobileUO)
- [x] Custom admin socket plugin (`shard/ClaudeUO.Admin`)
- [x] 6-hour restart countdown with 11 broadcasts &mdash; scripts under `automation/`
- [x] DigitalOcean Ubuntu 24.04 provisioning + systemd unit
- [x] GitHub Actions: CI build + on-push deploy that re-arms the countdown
- [ ] **Pick an era / expansion.** Stock ModernUO ships with `expansions.json` set
  to "None". Edit `server/Distribution/Data/expansions.json` (or an overlay
  under `shard/Distribution-overlay/Data/`) when you've decided.
- [ ] **Provision the production server.** See `deploy/README.md`.
- [ ] **Add deploy secrets** to the GitHub repo: `DEPLOY_HOST`, `DEPLOY_USER`,
  `DEPLOY_SSH_KEY` (and optionally `DEPLOY_PORT`).

## Local dev

ModernUO's `global.json` pins **.NET SDK 10.0.201**. Install it from
<https://dotnet.microsoft.com/download> before building.

```bash
# Build server + shard overlay
dotnet build server/ModernUO.slnx -c Release
dotnet build shard/ClaudeUO.Admin/ClaudeUO.Admin.csproj -c Release

# Apply the assemblies.json overlay so the server loads ClaudeUO.Admin.dll
cp -av shard/Distribution-overlay/. server/Distribution/

# Run
cd server/Distribution
dotnet ModernUO.dll
```

First run walks you through a config prompt (admin account, listener address,
expansion). Then connect a ClassicUO client to `127.0.0.1:2593`.

## Upstream credits

- [ModernUO](https://github.com/modernuo/ModernUO) &mdash; GPL-3.0
- [ClassicUO](https://github.com/ClassicUO/ClassicUO) &mdash; BSD-4-Clause
- [MobileUO](https://github.com/VoxelBoy/MobileUO) &mdash; BSD-4-Clause

Custom code in this repo (everything under `shard/`, `automation/`, `deploy/`,
`.github/`, and `docs/`) is GPL-3.0 to match ModernUO.
