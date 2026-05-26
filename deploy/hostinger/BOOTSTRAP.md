# Hostinger setup: what is automated vs manual

## Run the automated setup (your laptop)

| Where | How |
|--------|-----|
| **Cursor** | Terminal panel: **View → Terminal** (or Ctrl+`) |
| **Folder** | `~/projects/hermes-agent` |
| **Command** | `./deploy/hostinger/bootstrap.sh` |

Preview without changes:

```bash
./deploy/hostinger/bootstrap.sh --dry-run
```

If API key attach fails, add the key in hPanel (below) then:

```bash
./deploy/hostinger/bootstrap.sh --skip-api
```

---

## Automation matrix

| Step | Who | Where | How |
|------|-----|--------|-----|
| Fix MCP config | **Done** | `~/.cursor/mcp.json` | `hostinger-mcp` inside `mcpServers` |
| List VPS / Docker project | **Me (MCP)** | Cursor chat | `VPS_getVirtualMachinesV1`, `VPS_getProjectListV1` |
| Read API token for scripts | **Script** | `~/.cursor/mcp.json` | `bootstrap.sh` reads `HOSTINGER_API_TOKEN` |
| Create SSH key | **Script** | `~/.ssh/id_ed25519_hostinger` | `bootstrap.sh` |
| Register + attach SSH key to VPS | **Script** | Hostinger API | `bootstrap.sh` (or hPanel fallback) |
| Write SSH config | **Script** | `~/.ssh/config` | Appends `Host hermes-hostinger` block |
| Write deploy env | **Script** | `deploy/hostinger/hostinger.env` | VM id, IP, docker project |
| Test SSH + docker ps | **Script** | Terminal | `bootstrap.sh` |
| Server report for Cursor | **Script** | `deploy/hostinger/.server-context.md` | `collect-context.sh` |
| Restart Hermes / read logs | **Me (MCP)** | Cursor chat | `VPS_restartProjectV1`, `VPS_getProjectLogsV1` |
| Edit Hermes **code** on server | **You + me after SSH** | VPS + container | git/image deploy (phase 2) |
| Reload Cursor after MCP fix | **You** | Cursor | Command Palette → **Developer: Reload Window** |

---

## Manual steps (only if bootstrap fails)

### A. Paste SSH key in Hostinger (if API attach fails)

| Where | How |
|--------|-----|
| **Browser** | https://hpanel.hostinger.com/ |
| **Navigate** | **VPS** → select your Hermes VPS |
| **Menu** | **SSH access** or **SSH keys** |
| **Action** | **Add SSH key** → paste file contents |
| **File on laptop** | `~/.ssh/id_ed25519_hostinger.pub` |

Show key in terminal:

```bash
cat ~/.ssh/id_ed25519_hostinger.pub
```

Then re-run:

```bash
cd ~/projects/hermes-agent
./deploy/hostinger/bootstrap.sh --skip-api
```

### B. Reload Cursor (after MCP changes)

| Where | How |
|--------|-----|
| **Cursor** | **Ctrl+Shift+P** (Cmd+Shift+P on Mac) |
| **Command** | `Developer: Reload Window` |

### C. Confirm MCP connected

| Where | How |
|--------|-----|
| **Cursor** | **Settings** → **MCP** (or **Features → MCP**) |
| **Check** | `hostinger-mcp` shows connected / green |

---

## After bootstrap succeeds

Ask in Cursor:

- *“Read server context and summarize my Hermes setup”*
- *“Show last 50 lines of Hermes docker logs”* (via MCP)
- *“Help me deploy a skill change”*

Server-specific values (VM id, IP, container id) are written to `deploy/hostinger/hostinger.env` by `bootstrap.sh` and summarized in `deploy/hostinger/.server-context.md` after `collect-context.sh`.
