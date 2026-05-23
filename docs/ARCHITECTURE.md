# Architecture

```
                            ┌──────────────────────────┐
                            │      Players (TCP)       │
                            │ ClassicUO   |   MobileUO │
                            └──────────┬───────────────┘
                                       │ :2593
                                       ▼
 ┌────────────────────────────────────────────────────────────────────┐
 │                  Hetzner Cloud VPS (Ubuntu 24.04)                  │
 │                                                                    │
 │  systemd: modernuo.service                                         │
 │   └─ dotnet ModernUO.dll                                           │
 │       ├─ UOContent.dll          (vanilla content)                  │
 │       └─ ClaudeUO.Admin.dll     ── localhost :2595 ───┐            │
 │                                                       │            │
 │                                                       ▼            │
 │  atd (system queue 'c')                       automation/          │
 │   ├─ T-6h broadcast.sh ...   ─────────────►   broadcast.sh         │
 │   ├─ T-5h broadcast.sh ...                    restart-now.sh       │
 │   ├─ ...                                                           │
 │   └─ T-0  restart-now.sh                                           │
 │                                                                    │
 └────────────────────┬───────────────────────────────────────────────┘
                      │ SSH (deploy user)
                      │
            ┌─────────┴─────────┐
            │  GitHub Actions   │
            │  on push to main  │
            └───────────────────┘
```

## Pieces

### Server: `server/` (submodule → ModernUO)

ModernUO is a .NET 10 RunUO-derived UO server. We don't modify it &mdash; the
submodule stays clean so we can `git submodule update --remote` to pull
upstream improvements.

The TCP listener (`:2593` by default) is the same legacy UO protocol that
ClassicUO and MobileUO both speak, so a single server serves both clients.

Auto-discovery: on startup ModernUO calls `AssemblyHandler.Invoke("Configure")`
([Projects/Server/Main.cs:441](../server/Projects/Server/Main.cs)) which finds
every static `Configure()` method across all loaded assemblies and runs them.
That's how our overlay hooks in without modifying core code.

### Clients: `client/` (ClassicUO) and `mobile/` (MobileUO)

Tracked here as submodules so the repo records which client versions we
support. Players install ClassicUO themselves; MobileUO is published via the
app stores. The server doesn't run either &mdash; they're reference checkouts.

A change to either submodule on `main` still triggers the deploy workflow,
which restarts the server with a 6h countdown. This matches the user's brief:
"Whenever the client or server codebases are changed, a server restart should
be scheduled."

### Shard overlay: `shard/`

`shard/ClaudeUO.Admin/` &mdash; small .NET project producing `ClaudeUO.Admin.dll`.
Its only feature is `AdminSocket.Configure()`, which opens a localhost-only
TCP listener accepting `BROADCAST <hue> <msg>`, `RESTART`, and `SHUTDOWN`
commands. The listener refuses to bind to anything but loopback.

`shard/Distribution-overlay/Data/assemblies.json` overrides the stock
`server/Distribution/Data/assemblies.json` to include `ClaudeUO.Admin.dll` in
the load list. `deploy/build.sh` copies the overlay into place after each
build.

### Automation: `automation/`

- `broadcast.sh <message> [hue]` &mdash; opens a TCP connection to `127.0.0.1:2595`
  and sends one BROADCAST command. Used by every queued `at` job.
- `restart-now.sh` &mdash; sends RESTART. ModernUO calls `Core.Kill(true)` which
  exits the process; systemd brings it back up.
- `schedule-restart.sh` &mdash; cancels any in-flight `at` jobs in queue `c`, then
  queues 11 broadcasts + a restart. Idempotent &mdash; safe to invoke multiple
  times; the latest invocation always wins.
- `cancel-restart.sh` &mdash; cancels everything in queue `c`.

We use the system `at` daemon (queue `c`) rather than a long-running
scheduler process because:
- The schedule is one-shot per push, not periodic.
- `at` jobs survive a server reboot.
- We get cancellation for free (`atrm`).

### Deploy: `deploy/`

- `provision.sh` &mdash; one-shot Hetzner bootstrap (run once as root).
- `modernuo.service` &mdash; systemd unit. Restart=always means a clean
  `Core.Kill(true)` shutdown cycles the process automatically.
- `build.sh` &mdash; `dotnet build` ModernUO + overlay, copy assemblies.json.
- `update-server.sh` &mdash; called over SSH by the GH Actions workflow:
  `git pull`, `build.sh`, then `schedule-restart.sh` to arm the countdown.

### CI/CD: `.github/workflows/`

- `ci.yml` &mdash; runs on every PR + push: builds everything, shellchecks the
  scripts. Catches build breakage before it hits the server.
- `deploy.yml` &mdash; runs on push to `main`: SSH to host, run
  `update-server.sh`. Concurrency is gated to `deploy-main` so two rapid
  pushes can't race the schedule reset.

## Why "deploy and schedule" instead of "deploy and restart immediately"?

The brief is explicit: changes schedule a restart 6 hours out, with player-
facing broadcasts counting down. So we deploy the new bits to disk *now* but
keep the old process running until the countdown expires. From a player POV
the world is uninterrupted for those 6 hours; the in-game broadcasts give
them time to wrap up.

If a second push arrives mid-countdown, `schedule-restart.sh` cancels the
in-flight `at` jobs and starts a fresh 6-hour timer with new broadcasts &mdash;
matching the user-confirmed "timer resets on new push" behavior.
