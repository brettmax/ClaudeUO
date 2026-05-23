# Deploy &mdash; Hetzner Cloud Ubuntu 24.04

Provisioning the production shard.

## One-time host setup

1. **Create a Hetzner Cloud server.** A `CX22` (2 vCPU, 4GB RAM) is plenty for a
   bring-up; bump up once you have player numbers. Image: Ubuntu 24.04. Add
   your SSH key during creation.

2. **Add a deploy key for the repo.** On your laptop:

   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/claudeuo_deploy -C "claudeuo-deploy"
   ```

   Add `~/.ssh/claudeuo_deploy.pub` as a deploy key on the GitHub repo (read
   access is enough). Copy the private half onto the server as
   `/home/claudeuo/.ssh/id_ed25519` later, or just clone over HTTPS.

3. **SSH in as root, then provision:**

   ```bash
   ssh root@YOUR_HETZNER_IP
   export CLAUDEUO_REPO=https://github.com/YOUR_USER/ClaudeUO.git   # or git@... if using deploy key
   curl -fsSL "https://raw.githubusercontent.com/YOUR_USER/ClaudeUO/main/deploy/provision.sh" | bash -s
   ```

   `provision.sh` installs .NET 10, creates the `claudeuo` user, clones the
   repo into `/opt/claudeuo`, builds, and starts `modernuo.service`.

4. **Confirm it's alive:**

   ```bash
   systemctl status modernuo.service
   journalctl -u modernuo.service -f
   ss -lnt | grep 2593     # UO client port
   ss -lnt | grep 2595     # ClaudeUO admin socket (loopback only)
   ```

## Wiring GitHub Actions

The deploy workflow (`.github/workflows/deploy.yml`) SSHes into the host on
each push to `main`, calls `deploy/update-server.sh`, which builds and arms
the 6-hour restart countdown.

Add these repository **secrets**:

| Secret name | Value |
| --- | --- |
| `DEPLOY_HOST` | The Hetzner IP or DNS name |
| `DEPLOY_USER` | `claudeuo` |
| `DEPLOY_SSH_KEY` | Private key paired with a public key added to `/home/claudeuo/.ssh/authorized_keys` |
| `DEPLOY_PORT` | (optional) defaults to `22` |

The `claudeuo` user must be allowed to run `deploy/update-server.sh` without
sudo &mdash; everything that script touches (the repo, the build, the `at`
queue) is already owned by that user.

## Common operations

| What | Command |
| --- | --- |
| Status | `systemctl status modernuo.service` |
| Logs (live) | `journalctl -u modernuo.service -f` |
| Restart now | `sudo systemctl restart modernuo.service` (skips broadcast countdown) |
| See queued restart jobs | `sudo -u claudeuo atq -q c` |
| Cancel the in-flight countdown | `sudo -u claudeuo bash /opt/claudeuo/automation/cancel-restart.sh` |
| Manually arm a 6h countdown | `sudo -u claudeuo bash /opt/claudeuo/automation/schedule-restart.sh` |
| Test a broadcast right now | `sudo -u claudeuo bash /opt/claudeuo/automation/broadcast.sh "test from cli"` |

## Ports

| Port | Purpose | Exposure |
| --- | --- | --- |
| 22/tcp | SSH | Internet |
| 2593/tcp | UO client login + game | Internet |
| 2595/tcp | ClaudeUO admin socket | **loopback only** (the plugin refuses non-loopback binds) |

If you change the admin socket port, set `claudeuo.adminPort` in
`/opt/claudeuo/server/Distribution/Configuration/modernuo.json`.
