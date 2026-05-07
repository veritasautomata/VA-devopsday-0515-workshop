# Sandboxing AI Coding Agents — Workshop Bundle

A complete 45-minute workshop on running AI coding agents in a sandbox. Everything you need to deliver it: slides, presenter notes, a working Docker setup that participants run on their laptops, attack scripts that exercise the defenses, and the email templates to communicate with attendees.

## What's in this bundle

```
.
├── README.md                          ← you are here
│
├── workshop/                          ← what YOU need to deliver the workshop
│   ├── README.md                          delivery checklist + email templates
│   ├── slides.html                        12-slide deck (open in any browser)
│   ├── slides.pptx                        PowerPoint version of the same deck
│   ├── PRESENTER_NOTES.md                 timing, talking points, contingencies
│   ├── HANDOUT.md                         one-page reference for participants
│   └── prereq-check.sh                    script attendees run before the session
│
└── opencode-pipelock/                 ← the WORKSHOP REPO — host this on GitHub
    ├── README.md                          README for participants who clone the repo
    ├── docker-compose.yaml                two-container topology (agent + pipelock)
    ├── Dockerfile                         agent container image (bun + opencode + pipelock)
    ├── .dockerignore
    ├── .env.example                       template for OPENCODE_API_KEY
    ├── pipelock.yaml                      pipelock policy (allowlists, scanners, DLP)
    ├── opencode.json                      opencode config (MCP wrapping, disabled webfetch)
    ├── workspace/
    │   └── AGENTS.md                      tells the agent how to fetch via pipelock
    └── attacks/                           three runnable attack scripts (slide 10)
        ├── README.md
        ├── 01-blocklist.sh
        ├── 02-dlp.sh
        └── 03-entropy.sh
```

## How the pieces fit together

The two top-level folders serve different purposes and live in different places:

**`workshop/`** is the presenter's kit. It stays with you. You open `slides.html` (or `slides.pptx`) on the projector, you keep `PRESENTER_NOTES.md` open in another window for timing, you print or share `HANDOUT.md` to attendees.

**`opencode-pipelock/`** is the workshop repo. **Push this to a public GitHub repository** before the workshop. Attendees clone it during the session — slide 8 has them run `git clone <your-workshop-repo-url>`. Everything in this folder runs on their laptop.

The `prereq-check.sh` lives in `workshop/` because it's a presenter-distributed asset (you send it in the day-before email), but you'll also want to commit a copy to the workshop repo so the URL `<workshop-repo>/raw/main/prereq-check.sh` works for the curl-pipe-to-bash one-liner.

## Placeholders you need to fill in

A few spots reference `<workshop-repo>` as a placeholder for the GitHub URL you haven't created yet. Search and replace these with your actual repo URL before delivering:

```sh
# From the bundle root, after extracting:
grep -rn "<workshop-repo>" .
```

You'll find them in:
- `workshop/slides.html` (slide 8 git clone command, slide 12 resources)
- `workshop/slides.pptx` (same two spots — search inside PowerPoint)
- `workshop/HANDOUT.md`
- `workshop/README.md` (email templates)

The repo URL format that works in all of them is something like `https://github.com/<your-org>/opencode-pipelock-workshop`.

## Quickstart for the presenter

1. **Create the workshop repo on GitHub.** Push the contents of `opencode-pipelock/` plus a copy of `workshop/prereq-check.sh` to a public repo. A name like `opencode-pipelock-workshop` works.

2. **Replace placeholders.** Run `grep -rn "<workshop-repo>" workshop/` and update each match with your actual repo URL. For the `.pptx`, open in PowerPoint, use Find & Replace.

3. **Test the demo cold.** From a clean checkout of your workshop repo:
   ```sh
   cp .env.example .env       # paste a real OPENCODE_API_KEY
   docker compose build agent  # ~2 min first time
   docker compose up -d pipelock
   docker compose run --rm agent
   ```
   Inside the agent container, run all three `attacks/*.sh` scripts. Confirm each one is blocked.

4. **Send the prereq email** one week before. Template is in `workshop/README.md`.

5. **Send the reminder email** one day before with the prereq-check.sh URL.

6. **Read `workshop/PRESENTER_NOTES.md` end-to-end** at least once before delivering. It has the timing breakdowns, the contingency plans for when Docker fails on a third of laptops, and the common questions you'll get.

## What participants experience

1. They get your prereq email a week out, install Docker, sign up for opencode zen
2. They get your reminder email the day before, run `curl ... | bash` to verify their setup
3. They show up to the workshop with their laptop, terminal open
4. Slide 8: they `git clone <your-workshop-repo>`, paste their key into `.env`, build the agent image
5. Slide 9: they boot pipelock, drop into the agent, prove the network isolation by watching `curl example.com` time out
6. Slide 10: they run the three attack scripts and watch each one get blocked
7. They take home `HANDOUT.md` and the workshop repo URL, and (ideally) run pipelock in audit mode against their real workflow that week

## Honest framing

A few things to internalize and pass on:

- **Pipelock is early-stage** (v0.1.4, ~30 stars at workshop time, one named maintainer). The architecture is sound; the code hasn't been heavily audited. Use this as a teaching tool and a starting point, not a finished product. Slide 7 says this out loud — don't paper over it.

- **Defense is layered, not absolute.** A determined attacker who controls the model can still chunk secrets through allowed channels. Pipelock raises the bar; it doesn't make the wall infinite. The workshop is calibrated around this.

- **The container is not a hardened sandbox.** It drops capabilities and `no-new-privileges`, but anything inside `/workspace` is fair game for the agent. Don't bind-mount your home directory in.

- **45 minutes is tight for a hands-on session.** First-time delivery will run long. Test cold beforehand. The presenter notes flag where to cut if you're losing time.

## Adapting

The presenter notes and the workshop README cover adaptations:

- **Different length:** 30 min, 60 min, half-day variants are sketched in `workshop/README.md`
- **Different audience:** security-folks vs senior devs vs newcomers, all sketched in the same place
- **Different tool:** swap pipelock for any forward proxy with similar capabilities; the network-isolation pattern is tool-agnostic
- **Different agent:** swap opencode for Claude Code, Cursor, Cline, Aider — only `opencode.json` and the API allowlist change

## Feedback

If you deliver this workshop and find rough edges — a slide that doesn't land, a command that broke for half the room, a question you didn't see coming — that feedback is worth more than the workshop itself. Note it down. The next iteration always benefits.
