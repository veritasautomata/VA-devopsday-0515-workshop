#!/usr/bin/env bash
# Workshop prereq check.
#
# Run this BEFORE the workshop, from anywhere — it doesn't need the workshop
# repo cloned. It checks your Docker setup, network access to the registries
# we need, and a few CLI tools.
#
# This script does NOT read or create a .env file. The .env comes later, on
# slide 8 of the workshop, after you clone the workshop repo. The "API key"
# section here just checks if you've happened to export OPENCODE_API_KEY in
# your shell — almost no one will have, and that's fine. You'll paste it
# into .env during the session.
#
# Run with:    bash prereq-check.sh
# Or remotely: curl -fsSL <workshop-repo>/raw/main/prereq-check.sh | bash
#
# Paste the output if you hit FAILs.

set -uo pipefail

pass=0
fail=0
warn=0

ok()   { echo "  [ok]   $*";   pass=$((pass+1)); }
bad()  { echo "  [FAIL] $*";  fail=$((fail+1)); }
warn() { echo "  [warn] $*";  warn=$((warn+1)); }

section() { echo; echo "=== $1 ==="; }

section "Docker"
if command -v docker >/dev/null 2>&1; then
    ok "docker is installed: $(docker --version)"
    if docker info >/dev/null 2>&1; then
        ok "docker daemon is running"
    else
        bad "docker daemon is not running — start Docker Desktop"
    fi
else
    bad "docker not found — install Docker Desktop from docker.com"
fi

if docker compose version >/dev/null 2>&1; then
    ok "docker compose v2 available: $(docker compose version --short)"
else
    bad "docker compose v2 not found — Docker Desktop ships with this; update Docker"
fi

section "Hello-world test"
if docker run --rm hello-world >/dev/null 2>&1; then
    ok "docker can pull and run images"
else
    bad "docker run hello-world failed — check Docker, network, or disk space"
fi

section "Network"
if curl -fsS --max-time 5 https://github.com >/dev/null 2>&1; then
    ok "github.com reachable (needed for git clone)"
else
    bad "can't reach github.com — check your network/VPN"
fi
if curl -fsS --max-time 5 https://opencode.ai >/dev/null 2>&1; then
    ok "opencode.ai reachable (needed for opencode zen API)"
else
    warn "can't reach opencode.ai — workshop will partially work but the agent can't talk to its LLM"
fi
if curl -fsS --max-time 5 https://ghcr.io >/dev/null 2>&1; then
    ok "ghcr.io reachable (needed for pipelock image pull)"
else
    bad "can't reach ghcr.io — pipelock image pull will fail"
fi

section "Tools"
for tool in git curl jq; do
    if command -v "$tool" >/dev/null 2>&1; then
        ok "$tool installed"
    else
        warn "$tool not found — recommended but not strictly required"
    fi
done

section "Disk space"
avail_gb=$(df -BG . 2>/dev/null | awk 'NR==2 {gsub("G","",$4); print $4}')
if [ -n "${avail_gb:-}" ] && [ "$avail_gb" -ge 5 ] 2>/dev/null; then
    ok "${avail_gb}G free in current directory (need ~3G for the build)"
elif [ -n "${avail_gb:-}" ]; then
    warn "only ${avail_gb}G free — build needs ~3G, might be tight"
else
    warn "couldn't determine free space"
fi

section "Optional: opencode zen API key"
# If not already in env, try loading from a .env in the same directory as this script
if [ -z "${OPENCODE_API_KEY:-}" ]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$script_dir/.env" ]; then
        # shellcheck disable=SC1091
        set -a; source "$script_dir/.env"; set +a
    fi
fi
if [ -n "${OPENCODE_API_KEY:-}" ]; then
    ok "OPENCODE_API_KEY is set (found in .env or environment)"
else
    warn "OPENCODE_API_KEY not set — paste it into .env before the workshop. Get one at https://opencode.ai/zen"
fi

echo
echo "============================================"
echo "  passed: $pass    warnings: $warn    failed: $fail"
echo "============================================"
if [ "$fail" -gt 0 ]; then
    echo "Fix the FAILs before the workshop. Paste this whole output if you need help."
    exit 1
elif [ "$warn" -gt 0 ]; then
    echo "Warnings are okay — you'll be fine. Read them in case any apply to you."
    exit 0
else
    echo "All clear. See you at the workshop."
    exit 0
fi
