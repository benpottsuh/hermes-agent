# Re-authenticate OpenAI Codex (no API key)

Use ChatGPT / Codex **OAuth** so Hermes uses your subscription, not `OPENAI_API_KEY`.

## Active device login (when started by Cursor)

1. **Browser:** https://auth.openai.com/codex/device  
2. **Code:** shown in chat (one-time, ~10 minutes)  
3. Sign in with your OpenAI / ChatGPT account  
4. Approve access for Codex  

## Or run yourself

**Where:** Cursor terminal on your laptop (after `./deploy/hostinger/bootstrap.sh`)

```bash
source deploy/hostinger/hostinger.env
ssh "${SSH_HOST}" docker exec -it -u hermes -e HERMES_HOME=/opt/data "${DOCKER_CONTAINER}" \
  hermes auth add openai-codex --no-browser
```

Copy the URL + code, complete in browser, wait until the command says success.

## After login

```bash
source deploy/hostinger/hostinger.env
docker exec -u hermes -e HERMES_HOME=/opt/data "${DOCKER_CONTAINER}" hermes config set model.provider openai-codex
docker exec -u hermes -e HERMES_HOME=/opt/data "${DOCKER_CONTAINER}" hermes config set model.default gpt-5.5
docker exec -u hermes -e HERMES_HOME=/opt/data "${DOCKER_CONTAINER}" hermes auth list
```

Restart the Hermes Docker project in hPanel (or use Hostinger MCP `VPS_restartProjectV1`).

Test on your messaging platform — you should not see HTTP 401 or an unexpected model fallback.
