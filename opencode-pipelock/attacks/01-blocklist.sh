#!/bin/sh
# Attempt 1 — naive curl to a known-bad domain.
#
# Pastebin is on pipelock's blocklist by default, so this should be refused
# at the proxy with a 403. Run this from INSIDE the agent container.
#
# Expected output:
#   403 Forbidden — domain on blocklist
#
# What this proves: the simplest defense is a denylist of known
# exfiltration domains. Limited but real.

set -eu

echo "→ Attack 1: curl to a known-bad domain via pipelock"
echo "  curl -x http://pipelock:8888 https://pastebin.com/raw/test"
echo ""

curl -sS -o /dev/null -w "%{http_code}\n" \
     -x http://pipelock:8888 \
     -H "X-Pipelock-Agent: opencode-attack-test" \
     https://pastebin.com/raw/test || true

echo ""
echo "If you saw 403, the blocklist worked."
echo "If you saw something else, your pipelock config doesn't include pastebin"
echo "in its blocklist — check pipelock.yaml: fetch_proxy.monitoring.blocklist"
