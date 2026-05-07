# Workshop: sandboxing AI coding agents

A 45-minute lightning workshop for developers new to AI agents. By the end, participants have a working sandbox setup running on their laptop and a mental model for agent threats.

## What's in this folder

| File | Purpose |
|---|---|
| `slides.html` | The deck. Open in a browser. <kbd>←</kbd> <kbd>→</kbd> to navigate. Click left/right halves of screen also works. Single self-contained file — no build, no internet needed during delivery. |
| `PRESENTER_NOTES.md` | What you actually say, slide by slide. Timing cues, talking points, contingencies. Read this end-to-end before delivering. |
| `HANDOUT.md` | One-pager for participants. Print or share digitally. Has the commands, the mental model, and a take-home checklist. |
| `prereq-check.sh` | Bash script participants run *before* the workshop. Pass/fail with clear errors. Sent in the day-before email. |

The actual workshop *content* — the Docker Compose setup, pipelock config, Dockerfile — lives in a separate **workshop repo** that participants clone during the session. (See "Workshop repo prep" below.)

## Delivery checklist

### One week before

- [ ] Send the **prereq email** (template below)
- [ ] Push the workshop repo to a public GitHub URL participants can clone
- [ ] Build and push the agent image to a public registry as a fallback (`ghcr.io/<you>/opencode-pipelock-agent:workshop`)
- [ ] Test the slides on the projector resolution you'll be using

### One day before

- [ ] Send the **reminder email** with the prereq-check script
- [ ] Run the full demo cold yourself, end-to-end, timed
- [ ] If your `docker compose build` takes >2 min, plan to have participants build before the session

### Day of, 30 min before

- [ ] Open `slides.html` in fullscreen
- [ ] Pre-cd terminal to the workshop repo with `.env` populated
- [ ] Open second terminal for the audit log demo on slide 10
- [ ] Open browser tabs: `opencode.ai/zen`, the workshop repo, the pipelock GitHub
- [ ] Run `docker compose build agent` so the image is cached on your machine
- [ ] Test the projector. Do not skip this.

### After

- [ ] Share the workshop repo URL one more time
- [ ] Share the slide deck URL (it's just an HTML file, host it anywhere)
- [ ] Ask for one piece of feedback from each attendee — what was the most confusing part?

## Email templates

### Prereq email (1 week before)

> **Subject:** Workshop prereqs — sandboxing AI coding agents
>
> Hi — workshop is next [day]. To make sure we can spend the time on the actual content, please get these set up beforehand:
>
> 1. **Docker Desktop installed and running** ([docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop))
> 2. **A working terminal** (anything — iTerm, Windows Terminal, default macOS Terminal)
> 3. **An opencode zen API key** — sign up at [opencode.ai/zen](https://opencode.ai/zen). They give you free credit, and the workshop costs maybe 50¢ of API usage. Bring the key with you.
> 4. **Clone the workshop repo:** `git clone <workshop-repo-url>`
>
> Quick check: `docker run hello-world` should print a "Hello from Docker!" message. If it doesn't, fix that first.
>
> A more thorough check script will arrive the day before. See you [day]!

### Reminder email (1 day before)

> **Subject:** Workshop tomorrow — quick check
>
> See you tomorrow at [time]. To save time, please run this check before you arrive:
>
> ```sh
> curl -fsSL <workshop-repo>/raw/main/prereq-check.sh | bash
> ```
>
> If it prints "All clear" you're set. If it prints any FAILs, reply with the output and I'll help.
>
> Optional but recommended — pre-build the agent image so we don't wait on it during the session:
>
> ```sh
> cd opencode-pipelock-workshop
> docker compose build agent
> ```
>
> Bring your opencode zen API key. See you [time, location].

## Workshop repo prep

Participants clone a separate repo during the session that contains all the working files. That repo should be the `opencode-pipelock` setup we built earlier — `Dockerfile`, `docker-compose.yaml`, `pipelock.yaml`, `opencode.json`, `.env.example`, plus its own `README.md`.

Recommended additions specific to the workshop version:

1. **Pre-built image fallback.** Push `ghcr.io/<you>/opencode-pipelock-agent:workshop` and reference it in the compose file as a fallback for participants who can't build. Add to compose:

   ```yaml
   agent:
     image: ghcr.io/<you>/opencode-pipelock-agent:workshop  # fallback
     build:
       context: .
       dockerfile: Dockerfile
   ```

2. **Attack scripts.** Add a `attacks/` directory with the three attack attempts from slide 10 as runnable scripts:
   - `attacks/01-blocklist.sh` — pastebin curl
   - `attacks/02-dlp.sh` — fake key in URL
   - `attacks/03-entropy.sh` — base64 blob

   So participants can run `bash attacks/01-blocklist.sh` rather than typing the curl by hand.

3. **A pre-populated `.env.example`** with a comment pointing to opencode.ai/zen.

## Adapting this workshop

### Different tool

Swap pipelock for any egress proxy that supports MCP wrapping. The slides don't change much — the concepts are tool-agnostic. Update slide 7, the install commands, and the attack/defense slide.

### Different agent

Swap opencode for Claude Code, Cursor, Cline, OpenHands, Aider. The Docker isolation pattern is identical; only `opencode.json` and the LLM endpoint change. Adjust slide 8's commands and the allowlist in `pipelock.yaml`.

### Different length

- **30 min:** cut slide 4 down to 2 minutes, drop attack attempt 3 on slide 10, skip slide 11 (move take-home to handout).
- **60 min:** add a slide between 6 and 7 showing the actual `docker-compose.yaml` annotated. Add a slide after 11 covering MCP scanning live.
- **Half day:** add hands-on tuning the allowlist for a real codebase, and a "find the bypass" CTF-style segment using the pipelock test fixtures.

### Different audience

- **Security folks:** drop slide 4 (they know what an agent is), expand slide 5 with OWASP Agentic Top 10 mapping, end with adversarial scenarios.
- **Senior devs who already use agents:** skip slides 4-5, spend more time on slide 10 attacks, add a slide on threat modeling their existing setup.

## Notes on the slide deck

The deck is one HTML file. No build, no dependencies, works offline. Open it in any browser. The terminal aesthetic (monochrome, monospace, accent colors only for danger/safe states) is deliberate — this is a security topic and shouldn't feel like a SaaS pitch.

Keyboard:
- <kbd>→</kbd> <kbd>Space</kbd> <kbd>PageDown</kbd> — next slide
- <kbd>←</kbd> <kbd>PageUp</kbd> — previous slide
- <kbd>Home</kbd> / <kbd>End</kbd> — first / last
- <kbd>P</kbd> — open presenter notes in a new tab
- Click right half of screen — next; click left half — previous

URL hash deep-links to a specific slide: `slides.html#5` opens slide 5. Useful if you need to restart and skip ahead.
