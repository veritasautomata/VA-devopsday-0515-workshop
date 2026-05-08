#!/bin/sh
# Demo 5 — PII redaction in MCP tool responses.
#
# The scenario: your agent calls a CRM or database MCP tool that returns a
# customer record. The record contains real PII — credit card number, email,
# SSN. Pipelock scans the response BEFORE it reaches the model and either
# blocks it entirely (action: block) or strips the sensitive fields and
# delivers the rest (action: strip).
#
# This demo shows:
#   Part A: raw MCP response containing PII
#   Part B: what pipelock mcp scan catches (pattern name, matched text, position)
#   Part C: what the model would receive in strip mode (PII redacted, data intact)
#   Part D: how to add your own PII patterns (the one-line rule format)
#
# Run from inside the agent container:
#   cd /workspace/attacks && sh 05-pii-redaction.sh

set -eu

PIPELOCK_CONFIG=/etc/pipelock/pipelock.yaml

# ── helpers ──────────────────────────────────────────────────────────────────

divider() { echo; echo "────────────────────────────────────────────────────"; echo "  $1"; echo "────────────────────────────────────────────────────"; echo; }

# Build a realistic-looking MCP tool response from a fake CRM tool.
# Contains three PII signals: email, credit card, and SSN.
# node is used so embedded newlines in the text field are escaped correctly.
mcp_crm_response() {
  node -e "
    process.stdout.write(JSON.stringify({
      jsonrpc: '2.0', id: 7,
      result: { content: [{ type: 'text', text: [
        '# Customer Record — ID 4821',
        '',
        '## Contact',
        'Name:    Jane Doe',
        'Email:   jane.doe@example.com',
        'Phone:   555-867-5309',
        '',
        '## Billing',
        'Plan:    Pro Monthly',
        'Card:    4532123456789012',
        'Expires: 09/27',
        '',
        '## Identity',
        'SSN:     123-45-6789',
        '',
        '## Notes',
        'Customer since 2021. Prefers email contact. No open support tickets.'
      ].join('\\n') }] }
    }) + '\\n'
  )"
}

# ── Part A: show the raw response ─────────────────────────────────────────────

divider "PART A — the raw MCP tool response"

echo "This is what a CRM tool returns when the agent asks for a customer record:"
echo ""
mcp_crm_response | node -e "
  const raw = require('fs').readFileSync('/dev/stdin','utf8').trim();
  const obj = JSON.parse(raw);
  console.log(obj.result.content[0].text);
"
echo ""
echo "Three PII signals:"
echo "  · Email      jane.doe@example.com"
echo "  · Credit card  4532123456789012  (Visa format)"
echo "  · SSN          123-45-6789"

# ── Part B: run pipelock mcp scan ────────────────────────────────────────────

divider "PART B — pipelock mcp scan (what gets caught)"

echo "Piping the response through pipelock mcp scan --json ..."
echo ""

mcp_crm_response | pipelock mcp scan --config "$PIPELOCK_CONFIG" --json | node -e "
  const lines = require('fs').readFileSync('/dev/stdin','utf8').trim().split('\\n');
  lines.forEach(l => {
    const v = JSON.parse(l);
    if (!v.clean) {
      console.log('  RESULT   : BLOCKED (' + v.matches.length + ' match' + (v.matches.length > 1 ? 'es' : '') + ')');
      console.log('  Action   : ' + v.action);
      console.log('');
      v.matches.forEach((m, i) => {
        console.log('  Match ' + (i+1) + ':');
        console.log('    Pattern  : ' + m.pattern_name);
        console.log('    Matched  : \"' + m.match_text + '\"');
        console.log('    Position : byte ' + m.position);
        console.log('');
      });
    } else {
      console.log('  RESULT : CLEAN — no PII detected');
    }
  });
" || true

echo "The model never sees the PII — pipelock intercepts the tool response"
echo "before opencode processes it."

# ── Part C: strip mode — deliver data without PII ─────────────────────────────

divider "PART C — strip mode (PII redacted, record intact)"

echo "In strip mode pipelock removes the matched lines and delivers the rest."
echo "The model still gets the useful context — just not the sensitive values."
echo ""
echo "What the model would receive:"
echo ""

mcp_crm_response | node -e "
  const raw = require('fs').readFileSync('/dev/stdin','utf8').trim();
  const obj = JSON.parse(raw);
  const text = obj.result.content[0].text;

  // Simulate strip: redact lines matching PII patterns
  const emailRe    = /\b[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}\b/;
  const ccRe       = /\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|6(?:011|5[0-9]{2})[0-9]{12})\b/;
  const ssnRe      = /\b\d{3}[- ]\d{2}[- ]\d{4}\b/;

  const stripped = text.split('\n').map(line => {
    if (emailRe.test(line)) return line.replace(emailRe, '[REDACTED-EMAIL]');
    if (ccRe.test(line))    return line.replace(ccRe,    '[REDACTED-CARD]');
    if (ssnRe.test(line))   return line.replace(ssnRe,   '[REDACTED-SSN]');
    return line;
  }).join('\n');

  console.log(stripped);
"

echo ""
echo "To switch to strip mode, edit pipelock.yaml:"
echo "  response_scanning:"
echo "    action: strip   # was: block"
echo ""
echo "Reload without restarting:"
echo "  docker kill --signal SIGHUP pipelock   (run from the host)"

# ── Part D: adding your own PII pattern ──────────────────────────────────────

divider "PART D — adding your own PII pattern"

echo "Every PII rule in pipelock.yaml follows the same format."
echo "Open pipelock.yaml and add to response_scanning.patterns:"
echo ""
echo "  # UK National Insurance number"
echo "  - name: \"PII — UK NI Number\""
echo "    regex: '\\b[A-Z]{2}[0-9]{6}[A-D ]\\b'"
echo ""
echo "  # IPv4 address (if you don't want internal IPs surfaced)"
echo "  - name: \"PII — IPv4 Address\""
echo "    regex: '\\b(?:[0-9]{1,3}\\.){3}[0-9]{1,3}\\b'"
echo ""
echo "  # US Passport number"
echo "  - name: \"PII — US Passport\""
echo "    regex: '\\b[A-Z][0-9]{8}\\b'"
echo ""
echo "After saving, reload pipelock:"
echo "  docker kill --signal SIGHUP pipelock"
echo ""
echo "Test any pattern immediately:"
echo "  echo '{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"NI: AB123456C\"}]}}' \\"
echo "    | pipelock mcp scan --config /etc/pipelock/pipelock.yaml --json | jq ."
echo ""
echo "See pii-custom-rules.md in the repo root for a full pattern library."
