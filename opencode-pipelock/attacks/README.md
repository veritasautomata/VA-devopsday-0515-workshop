# Attack scripts

Three scripts that try to exfiltrate fake secrets through pipelock. Each one is supposed to fail. Run them from inside the agent container during the workshop's hands-on segment.

## Setup

These need to run from inside the agent container (where pipelock is reachable as `pipelock:8888`):

```sh
# From the host, drop into the agent
docker compose run --rm agent

# Inside the container, the attacks/ dir is at /workspace/attacks
cd /workspace/attacks
sh 01-blocklist.sh
sh 02-dlp.sh
sh 03-entropy.sh
```

## What each one tests

| Script | Defense it triggers | Bypass complexity |
|---|---|---|
| `01-blocklist.sh` | Domain blocklist (pastebin) | Trivial — use any domain not on the list |
| `02-dlp.sh` | Regex match for Anthropic key format | Easy — put the key in a body, encode it |
| `03-entropy.sh` | Shannon entropy threshold on URL params | Hard — needs low-entropy encoding or chunking |

## Watching pipelock react

Open a second terminal on the host and tail the audit log:

```sh
docker compose logs -f pipelock | jq 'select(.blocked == true)'
```

You'll see one JSON line per blocked request, with the rule that triggered, the source identifier (the `X-Pipelock-Agent` header), and the URL.

## Important: these use FAKE keys

The "API keys" in these scripts are placeholder strings designed to match pipelock's regex without being real credentials. **Don't substitute real keys to "make it more realistic."** A pattern-matching scanner doesn't care whether the value is valid, and you don't want a real key in your shell history or any log.

## Find a bypass

Slide 10 of the workshop says "now try to bypass it" — that's the spirit. Real bypasses exist for each of these:

- **Blocklist:** trivially defeated by any unlisted domain. The blocklist is a defense-in-depth signal, not a wall.
- **DLP:** defeated by encoding the key (rot13, base64, custom). Caught by attack 3's entropy check — until you encode in a way that has natural-language entropy.
- **Entropy:** defeated by chunking, by encoding into wordlists, by DNS tunneling, by abusing allowlisted endpoints (e.g. github gists).

The point of the workshop isn't "pipelock makes you safe." It's "every layer of defense is bypassable, but together they raise the bar enough that a compromised agent has to be sophisticated and pre-planned to succeed — and most prompt injections aren't."
