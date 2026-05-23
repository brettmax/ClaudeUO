# Restart automation

The shard reschedules a clean restart **6 hours after** any push to `main`
(server, client, or shard overlay change). Players see in-game broadcasts
ramp up as the restart approaches.

## Broadcast schedule

| Offset from push | Message |
| --- | --- |
| `+0:00`  (T-6h) | "The server will restart in 6 hours." |
| `+1:00`  (T-5h) | "The server will restart in 5 hours." |
| `+2:00`  (T-4h) | "The server will restart in 4 hours." |
| `+3:00`  (T-3h) | "The server will restart in 3 hours." |
| `+4:00`  (T-2h) | "The server will restart in 2 hours." |
| `+4:30`  (T-1h30m) | "The server will restart in 90 minutes." |
| `+5:00`  (T-1h)  | "The server will restart in 1 hour." |
| `+5:15`  (T-45m) | "The server will restart in 45 minutes." |
| `+5:30`  (T-30m) | "The server will restart in 30 minutes." |
| `+5:45`  (T-15m) | "The server will restart in 15 minutes." |
| `+5:55`  (T-5m, final) | "The server will restart in 5 minutes. Please log out safely." |
| `+6:00`  (T-0) | `Core.Kill(true)` &mdash; restart |

Hourly for the first four hours, every 30 minutes for the next hour, every 15
minutes for the last hour, with the would-be `T-0` announcement skipped in
favour of a final `T-5m` warning.

## How it works

1. `git push origin main` (or merge a PR).
2. `.github/workflows/deploy.yml` SSHes into the host and runs
   `deploy/update-server.sh`.
3. `update-server.sh` pulls + builds, then calls
   `automation/schedule-restart.sh`.
4. `schedule-restart.sh` cancels any existing `at` jobs in queue `c`
   (`atrm $(atq -q c | awk '{print $1}')`) and queues the 12 jobs above.
5. As each `at` job fires it shells out to `automation/broadcast.sh`, which
   opens a TCP connection to the in-process admin socket on `127.0.0.1:2595`
   and sends a `BROADCAST` command. The plugin posts
   `World.Broadcast(hue, true, message)` onto the game loop.
6. The final job (`automation/restart-now.sh`) sends `RESTART`; the plugin
   calls `Core.Kill(true)`; ModernUO exits; systemd brings it back up.

## What if a second push arrives mid-countdown?

`schedule-restart.sh` always starts with `atrm` on the existing queue, so the
latest push wins &mdash; the timer resets to a fresh 6 hours and broadcasts
re-announce from `T-6h`. If you want the opposite (first push wins, later
pushes ride along), the only change is removing the `atrm` block at the top
of `schedule-restart.sh`.

## Operating it by hand

```bash
# Inspect what's queued
sudo -u claudeuo atq -q c

# Show the actual shell that's about to run for job 7
sudo -u claudeuo at -c 7 | tail

# Wipe the queue without queuing a replacement
sudo -u claudeuo bash /opt/claudeuo/automation/cancel-restart.sh

# Arm a 6h countdown by hand (e.g. after a config-only change you didn't push)
sudo -u claudeuo bash /opt/claudeuo/automation/schedule-restart.sh

# Bypass the countdown and restart now
sudo -u claudeuo bash /opt/claudeuo/automation/restart-now.sh
# (or, equivalently, the systemd way:)
sudo systemctl restart modernuo.service

# Ad-hoc broadcast (doesn't change the schedule)
sudo -u claudeuo bash /opt/claudeuo/automation/broadcast.sh "Maintenance complete." 53
```

## Smoke-testing the wiring

You don't want to wait 6 hours to know if the schedule plumbing is broken.
Run a fast dry run:

```bash
# As the claudeuo user, queue a 2-minute "restart" instead of a 6-hour one:
echo '/opt/claudeuo/automation/broadcast.sh "wiring test"' | at -q c now + 1 minutes
atq -q c    # confirms the job is queued
```

If the broadcast appears in-game one minute later, the path GitHub Actions →
host → `at` → admin socket → `World.Broadcast` is healthy.

## Failure modes &amp; what they look like

| Symptom | Likely cause |
| --- | --- |
| GH Actions deploy step fails at "Pull, build, and re-arm" with SSH error | Wrong host/user/key in secrets, or the deploy user can't read `/opt/claudeuo` |
| Deploy succeeds, but `atq -q c` shows nothing | `atd` not running. `systemctl status atd`; `systemctl enable --now atd` |
| Broadcasts queued but never appear in-game | Admin socket not bound. Check `journalctl -u modernuo -g 'admin socket'`. If the plugin refused to bind, `claudeuo.adminBind` is probably set to something non-loopback in `modernuo.json` |
| `BROADCAST` command replies `ERR ...` | Message contained no text after the hue, or hue isn't an integer |
| Restart fires but the server stays down | Check `journalctl -u modernuo -n 200`. systemd `Restart=always` should bring it back; if not, the build is broken |
