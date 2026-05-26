# Fix SSH: key attached in hPanel but login still fails

Hostinger may show your SSH key as attached to the VM, but login still fails if the public key was never written to `~/.ssh/authorized_keys` on the running VPS.

## Fix (about 3 minutes) — browser only

### Where: Hostinger hPanel

1. Open **https://hpanel.hostinger.com/** and log in.
2. Go to **VPS** → select your Hermes VPS.
3. Open **Browser terminal** (or **Terminal** / **noVNC** — in-browser console, not your laptop SSH).
4. Log in as **root** using the password from:
   - **VPS** → your server → **Settings** → **SSH access** → **Root password**  
   (or **Access** → **Root password**, depending on panel layout).

### What to paste in that browser terminal

On your **laptop**, print your public key:

```bash
cat ~/.ssh/id_ed25519_hostinger.pub
```

On the **browser terminal**, run (replace `YOUR_PUBLIC_KEY_LINE` with the full line from `cat`):

```bash
mkdir -p /root/.ssh
chmod 700 /root/.ssh
echo 'YOUR_PUBLIC_KEY_LINE' >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
grep -c ed25519 /root/.ssh/authorized_keys
```

Last line should print `1` or higher.

Optional — allow SSH if firewall blocks port 22:

```bash
ufw allow 22/tcp 2>/dev/null; ufw reload 2>/dev/null; ufw status | head -5
```

### Where: your laptop (Cursor terminal)

```bash
cd ~/projects/hermes-agent
ssh hermes-hostinger 'echo SSH_OK && docker ps | grep hermes'
./deploy/hostinger/bootstrap.sh --skip-api
```

---

## If root password login fails in browser terminal

Some VPS templates disable root password. In hPanel:

- **VPS** → your server → **Settings** → **Reset root password**, then retry browser terminal.

---

## If you use an hPanel “SSH user” (not root)

If you created a separate SSH user in hPanel (not `root`), update `~/.ssh/config`:

```
Host hermes-hostinger
  User YOUR_HPanel_SSH_USERNAME
```

And add the same public key to `/home/YOUR_HPanel_SSH_USERNAME/.ssh/authorized_keys` in the browser terminal instead of `/root/.ssh/`.
