#!/bin/sh
# Demo 7 — PII strip mode and custom rules.
#
# Covers two things:
#
#   Part A — strip vs block
#     With action: block the entire MCP response is rejected and the model
#     sees a tool error. With action: strip only the matched PII lines are
#     redacted and the rest of the record is delivered. This demo simulates
#     strip output so you can see what the model would receive.
#
#   Part B — adding your own PII pattern
#     Every rule is one regex in pipelock.yaml. This part shows the format,
#     gives a worked example, and shows how to test a new rule immediately
#     without restarting pipelock.
#
# Run from inside the agent container:
#   cd /workspace/attacks && sh 07-pii-strip-rules.sh

set -eu

PIPELOCK_CONFIG=/etc/pipelock/pipelock.yaml

divider() { echo; echo "────────────────────────────────────────────────────"; echo "  $1"; echo "────────────────────────────────────────────────────"; echo; }

mcp_crm_response() {
  node -e "
    process.stdout.write(JSON.stringify({
      jsonrpc: '2.0', id: 7,
      result: { content: [{ type: 'text', text: [
        '# Customer Record — ID 4821',
        '',
        '## Contact',
        'Name:    Jane Doe',
        'Email:   jane.doe@acme-corp.com',
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

# ── Part A: strip vs block ────────────────────────────────────────────────────

divider "PART A — block vs strip"

echo "Current config: response_scanning.action = block"
echo "  The entire tool response is rejected."
echo "  The model sees: ToolError: MCP response blocked by pipelock — PII detected"
echo ""
echo "Alternative:    response_scanning.action = strip"
echo "  Only the lines matching PII patterns are redacted."
echo "  The model still gets the useful parts of the record."
echo ""
echo "What the model would receive in strip mode:"
echo ""

mcp_crm_response | node -e "
  const raw = require('fs').readFileSync('/dev/stdin','utf8').trim();
  const obj = JSON.parse(raw);
  const text = obj.result.content[0].text;

  const emailRe = /\b[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}\b/;
  const ccRe    = /\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|6(?:011|5[0-9]{2})[0-9]{12})\b/;
  const ssnRe   = /\b\d{3}[- ]\d{2}[- ]\d{4}\b/;

  const stripped = text.split('\n').map(line => {
    if (emailRe.test(line)) return line.replace(emailRe, '[REDACTED-EMAIL]');
    if (ccRe.test(line))    return line.replace(ccRe,    '[REDACTED-CARD]');
    if (ssnRe.test(line))   return line.replace(ssnRe,   '[REDACTED-SSN]');
    return line;
  }).join('\n');

  console.log(stripped);
"

echo ""
echo "The model can still answer 'what plan is this customer on?' and"
echo "'when did they join?' — it just can't see or leak the sensitive values."
echo ""
echo "To switch modes, edit pipelock.yaml:"
echo ""
echo "  response_scanning:"
echo "    action: strip   # was: block"
echo ""
echo "Reload without restarting (run from the HOST terminal):"
echo "  docker kill --signal SIGHUP pipelock"
echo ""
echo "Note: 'warn' is also valid — logs the match but lets the response through."
echo "      Start with warn when adding new patterns to tune for false positives."

# ── Part B: custom PII patterns ───────────────────────────────────────────────

divider "PART B — adding your own PII pattern"

echo "Add to BOTH sections of pipelock.yaml for end-to-end coverage:"
echo ""
echo "  dlp:                           ← blocks outbound requests with PII in URL"
echo "    patterns:"
echo "      - name: \"PII — UK NI Number\""
echo "        regex: '\\b[A-Z]{2}[0-9]{6}[A-D ]\\b'"
echo "        severity: high"
echo ""
echo "  response_scanning:             ← blocks MCP responses containing PII"
echo "    patterns:"
echo "      - name: \"PII — UK NI Number\""
echo "        regex: '\\b[A-Z]{2}[0-9]{6}[A-D ]\\b'"
echo ""

divider "Testing a new pattern without restarting"

echo "1. Edit pipelock.yaml and add your rule."
echo ""
echo "2. Reload (from the HOST terminal):"
echo "   docker kill --signal SIGHUP pipelock"
echo ""
echo "3. Test the MCP scanner immediately (from inside this container):"
echo ""

TEST_JSON='{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"Employee NI: AB123456C\nDept: Engineering"}]}}'
echo "   echo '$TEST_JSON' \\"
echo "     | pipelock mcp scan --config $PIPELOCK_CONFIG --json | jq ."
echo ""
echo "Running the test now against the current config ..."
echo "(No UK NI pattern is loaded yet — expect CLEAN)"
echo ""

printf '%s\n' "$TEST_JSON" \
  | pipelock mcp scan --config "$PIPELOCK_CONFIG" --json \
  | node -e "
    const v = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8').trim());
    console.log('  Result:', v.clean ? 'CLEAN (pattern not loaded yet)' : 'BLOCKED');
    if (!v.clean) v.matches.forEach(m => console.log('  Match:', m.pattern_name, '—', m.match_text));
  " || true

echo ""
echo "4. Test the DLP outbound scanner (from inside this container):"
echo "   curl -so /dev/null -w \"%{http_code}\" -x http://pipelock:8888 \\"
echo "     -H \"X-Pipelock-Agent: test\" \"http://github.com/x?ni=AB123456C\""
echo "   # expect 403 once the pattern is loaded"
echo ""
echo "See pii-custom-rules.md in the repo root for a full pattern library"
echo "covering financial, identity, contact, and healthcare PII."
