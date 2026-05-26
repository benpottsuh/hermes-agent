# Hostinger deploy workflow

Use this repo on your laptop (or in Cursor) for **code changes**, and your Hostinger VPS for **running** Hermes 24/7.

Hermes keeps **state** under `~/.hermes/` (config, memory, sessions, skills). The **source code** is what you sync from git.

## Layout

| Location | Purpose |
|----------|---------|
| This repo (`~/projects/hermes-agent`) | Edit agent code, skills, configs in git |
| VPS `~/hermes-agent` (recommended) | Same repo, `git pull` + reinstall |
| VPS `~/.hermes/` | Runtime data — **back up**, do not wipe on deploy |

## One-time VPS setup

SSH into Hostinger as your deploy user (not root):

```bash
# Clone (or use your fork)
git clone --recurse-submodules https://github.com/NousResearch/hermes-agent.git ~/hermes-agent
cd ~/hermes-agent

# Production install (matches upstream installer behavior)
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
hermes setup
hermes gateway setup   # Telegram, Discord, etc.
```

If you already installed via the one-liner, you only need a git clone at a known path and to point updates at it (see **Update from your repo** below).

## Local development (this machine)

```bash
cd ~/projects/hermes-agent
export PATH="$HOME/.local/bin:$PATH"

uv venv venv --python 3.11
export VIRTUAL_ENV="$(pwd)/venv"
uv pip install -e ".[all,dev]"

mkdir -p ~/.hermes
cp -n cli-config.yaml.example ~/.hermes/config.yaml 2>/dev/null || true
# Add keys to ~/.hermes/.env (never commit secrets)

ln -sf "$(pwd)/venv/bin/hermes" ~/.local/bin/hermes-dev
hermes-dev doctor
```

Use `hermes-dev` locally so you do not collide with a global `hermes` install.

## Day-to-day: change code → run on VPS

1. **Branch and commit** locally (skills, Python, config templates — not `~/.hermes/.env`).
2. **Push** to GitHub (your fork is recommended).
3. **Deploy** on Hostinger:

```bash
./deploy/hostinger/sync.sh user@your-vps-host ~/hermes-agent
```

Or SSH manually:

```bash
ssh user@your-vps-host 'cd ~/hermes-agent && git pull && uv pip install -e ".[all]" && systemctl --user restart hermes-gateway 2>/dev/null || hermes gateway restart'
```

4. **Verify**: `hermes doctor` on the VPS.

## Fork (recommended)

So you can push without writing to NousResearch directly:

```bash
git remote rename origin upstream
git remote add origin git@github.com:YOUR_USER/hermes-agent.git
git fetch upstream
git checkout -b my-changes
# after edits
git push -u origin my-changes
```

On the VPS, set `origin` to your fork and `git pull` from there.

## What to back up on the VPS

Before big upgrades:

```bash
tar czf hermes-state-backup.tgz -C ~ .hermes/config.yaml .hermes/.env .hermes/MEMORY.md .hermes/USER.md .hermes/skills .hermes/sessions 2>/dev/null
```

## Config only on the server

Keep secrets and channel tokens on the VPS in `~/.hermes/.env` and `~/.hermes/config.yaml`. Copy **examples** from this repo; do not commit live keys.
