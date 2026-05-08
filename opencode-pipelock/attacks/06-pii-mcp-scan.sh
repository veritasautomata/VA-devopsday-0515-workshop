#!/bin/sh
# Demo 6 — PII in MCP tool responses: local scanner (output appears here).
#
# Scenario: your agent calls a CRM MCP tool that returns a customer record.
# The record contains real PII — email, credit card, SSN. Pipelock scans the
# tool response BEFORE it reaches the model and blocks it.
#
# This scanner is LOCAL — it runs inside the agent container, not the proxy.
# Results appear in this terminal. Nothing appears in docker logs pipelock.
# (The proxy log shows network traffic; MCP response scanning runs in-process.)
#
# The same scanner fires automatically when any MCP server is wrapped with
# 'pipelock mcp proxy' in opencode.json — that's how the demo-notes server
# and filesystem server are protected in this sandbox.
#
# Run from inside the agent container:
#   cd /workspace/attacks && sh 06-pii-mcp-scan.sh

set -eu

PIPELOCK_CONFIG=/etc/pipelock/pipelock.yaml

divider() { echo; echo "────────────────────────────────────────────────────"; echo "  $1"; echo "────────────────────────────────────────────────────"; echo; }

# Build a realistic MCP tool response from a fake CRM tool.
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

# ── Step 1: show the raw tool response ───────────────────────────────────────

divider "Step 1 — raw MCP tool response from the CRM"

echo "This is what the tool returns when the agent asks for a customer record:"
echo ""

mcp_crm_response | node -e "
  const raw = require('fs').readFileSync('/dev/stdin','utf8').trim();
  const obj = JSON.parse(raw);
  console.log(obj.result.content[0].text);
"

echo ""
echo "Three PII signals present:"
echo "  · Email       jane.doe@acme-corp.com"
echo "  · Credit card 4532123456789012  (Visa)"
echo "  · SSN         123-45-6789"

# ── Step 2: run pipelock mcp scan ────────────────────────────────────────────

divider "Step 2 — pipelock mcp scan catches all three"

echo "Piping the tool response through pipelock mcp scan --json ..."
echo "(same engine that runs inside 'pipelock mcp proxy')"
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
        console.log('  Match ' + (i + 1) + ':');
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

# ── Step 3: what the model actually sees ─────────────────────────────────────

divider "Step 3 — what the model sees"

echo "With action: block (the default), the model receives a tool error:"
echo ""
echo "  ToolError: MCP response blocked by pipelock — PII detected"
echo ""
echo "The customer record never enters the model's context window."
echo ""
echo "To deliver the record with PII redacted instead, see:"
echo "  sh 07-pii-strip-rules.sh"
