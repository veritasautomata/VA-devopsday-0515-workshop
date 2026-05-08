# Custom PII Rules for Pipelock

How to add your own PII detection patterns to `pipelock.yaml` — and how to test them before deploying.

---

## Where rules live

Pipelock has two independent scanners. Add your PII rule to one or both depending on what you want to protect:

| Scanner | What it scans | Where in pipelock.yaml |
|---|---|---|
| **DLP** | Outbound requests — URLs and POST bodies the agent sends | `dlp.patterns` |
| **Response scanning** | Inbound MCP tool responses before they reach the model | `response_scanning.patterns` |

**Typical use:**
- Add to `dlp.patterns` if you want to stop the agent from **sending** PII to external services.
- Add to `response_scanning.patterns` if you want to stop a database or API from **surfacing** PII to the model.
- Add to both if you want end-to-end coverage.

---

## Rule format

### DLP pattern (outbound)

```yaml
dlp:
  patterns:
    - name: "Friendly name shown in audit logs"
      regex: 'your-regex-here'
      severity: critical   # critical | high | medium | low
```

### Response scanning pattern (inbound MCP)

```yaml
response_scanning:
  patterns:
    - name: "PII — Friendly name"
      regex: 'your-regex-here'
      # no severity field — response_scanning doesn't use it
```

---

## Pattern library

Copy-paste any of these into `pipelock.yaml`. All patterns use `\b` word boundaries to avoid false positives on partial matches.

### Financial

```yaml
# Visa, Mastercard, Amex, Discover (16-digit card numbers)
- name: "PII — Credit Card Number"
  regex: '\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|6(?:011|5[0-9]{2})[0-9]{12})\b'

# Any 13–16 digit number (looser — catches more, more false positives)
- name: "PII — Possible Card Number"
  regex: '\b(?:\d[ -]?){13,16}\b'

# ABA routing number (9 digits, first digit 0-3)
- name: "PII — Bank Routing Number"
  regex: '\b[0-3][0-9]{8}\b'

# IBAN (EU/UK bank accounts)
- name: "PII — IBAN"
  regex: '\b[A-Z]{2}[0-9]{2}[A-Z0-9]{4}[0-9]{7}(?:[A-Z0-9]{0,16})\b'
```

### Identity documents

```yaml
# US Social Security Number (dashes or spaces)
- name: "PII — US SSN"
  regex: '\b\d{3}[- ]\d{2}[- ]\d{4}\b'

# US Passport number
- name: "PII — US Passport"
  regex: '\b[A-Z][0-9]{8}\b'

# UK National Insurance Number
- name: "PII — UK NI Number"
  regex: '\b[A-Z]{2}[0-9]{6}[A-D ]\b'

# EU VAT number (catches most member states)
- name: "PII — EU VAT Number"
  regex: '\b[A-Z]{2}[0-9A-Z]{8,12}\b'

# US Driver's license (general pattern — varies by state)
- name: "PII — US Driver License"
  regex: '\b[A-Z][0-9]{7}\b|\b[0-9]{9}\b'
```

### Contact information

```yaml
# Email address
- name: "PII — Email Address"
  regex: '\b[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}\b'

# US/Canada phone (dashes, dots, or spaces)
- name: "PII — US Phone Number"
  regex: '\b(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]\d{3}[-.\s]\d{4}\b'

# International phone (E.164 format)
- name: "PII — International Phone"
  regex: '\+[1-9][0-9]{7,14}\b'

# US ZIP code (5 or 9 digit)
- name: "PII — US ZIP Code"
  regex: '\b[0-9]{5}(?:-[0-9]{4})?\b'

# UK postcode
- name: "PII — UK Postcode"
  regex: '\b[A-Z]{1,2}[0-9][0-9A-Z]?\s?[0-9][A-Z]{2}\b'
```

### Healthcare (HIPAA-relevant)

```yaml
# US NPI (National Provider Identifier)
- name: "PII — NPI Number"
  regex: '\b[0-9]{10}\b'

# ICD-10 diagnostic code
- name: "PHI — ICD-10 Code"
  regex: '\b[A-Z][0-9]{2}(?:\.[0-9A-Z]{1,4})?\b'

# DEA number (controlled substance prescriber)
- name: "PHI — DEA Number"
  regex: '\b[A-Z]{2}[0-9]{7}\b'

# Medical record number (MRN) — common format, adjust to your system
- name: "PHI — Medical Record Number"
  regex: '\bMRN[:\s]?[0-9]{6,10}\b'
```

### Infrastructure & tokens (overlap with DLP defaults)

```yaml
# IPv4 address (if you don't want internal IPs surfaced by tools)
- name: "PII — IPv4 Address"
  regex: '\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b'

# MAC address
- name: "PII — MAC Address"
  regex: '\b(?:[0-9A-Fa-f]{2}[:\-]){5}[0-9A-Fa-f]{2}\b'
```

---

## Testing a pattern before deploying

You don't need to restart pipelock or rebuild anything. Use `pipelock mcp scan` to test any rule directly:

```sh
# 1. Write your rule into a temp config (or edit pipelock.yaml directly)
# 2. Pipe a sample MCP response containing the PII through the scanner:

echo '{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"Customer SSN: 123-45-6789"}]}}' \
  | pipelock mcp scan --config /etc/pipelock/pipelock.yaml --json | jq .

# Expected: clean: false, matches[0].pattern_name = "PII — US SSN"
```

The scanner returns one JSON line per response. Key fields:

```json
{
  "clean": false,
  "action": "block",
  "matches": [
    {
      "pattern_name": "PII — US SSN",
      "match_text": "123-45-6789",
      "position": 28
    }
  ]
}
```

If `clean` is `true`, the rule didn't fire — check your regex and try again.

---

## Reloading after changes

Response scanning rules reload on SIGHUP — no container restart needed:

```sh
# From the host (not inside the agent container):
docker kill --signal SIGHUP pipelock
```

> **Note:** `forward_proxy` config changes (allowlist, entropy threshold) require a full restart:
> ```sh
> docker compose restart pipelock
> ```

---

## Choosing block vs strip

Set in `pipelock.yaml` under `response_scanning.action`:

| Mode | What happens | Best for |
|---|---|---|
| `block` | Entire tool response is rejected; model sees a tool error | Unattended production agents, any PII that should never reach the model |
| `strip` | Only the matched lines are redacted; rest is delivered | Cases where the tool response is still useful without the PII values |
| `warn` | Response passes through; pipelock logs the match | Audit / tuning mode — see what would be caught without breaking anything |

Start with `warn` when adding new patterns to measure false-positive rate. Switch to `strip` or `block` once you're confident in the regex.

---

## Tuning for false positives

Some patterns (especially phone numbers, ZIP codes, 9-digit NPI) will fire on non-PII content. Ways to tighten:

1. **Add context anchors** — require a label before the value:
   ```yaml
   # SSN only when preceded by "SSN:", "Social Security:", etc.
   regex: '(?i)(?:ssn|social security)[:\s]+\d{3}[- ]\d{2}[- ]\d{4}'
   ```

2. **Use negative lookahead** to exclude known-safe patterns:
   ```yaml
   # Phone, but not if it looks like a port number (not preceded by colon)
   regex: '(?<!:)\b\d{3}[-.\s]\d{3}[-.\s]\d{4}\b'
   ```

3. **Start with `warn` mode** and check the audit log after a real session:
   ```sh
   docker logs pipelock | jq 'select(.event == "warn") | .url, .pattern'
   ```

4. **Run `pipelock simulate`** to verify your new rules don't break the existing attack scenario score:
   ```sh
   docker exec pipelock /pipelock simulate --config /config/pipelock.yaml
   ```

---

## Complete example: adding UK NI number protection

1. Edit `pipelock.yaml`, add to both sections:

```yaml
dlp:
  patterns:
    # ... existing patterns ...
    - name: "PII — UK NI Number"
      regex: '\b[A-Z]{2}[0-9]{6}[A-D ]\b'
      severity: high

response_scanning:
  patterns:
    # ... existing patterns ...
    - name: "PII — UK NI Number"
      regex: '\b[A-Z]{2}[0-9]{6}[A-D ]\b'
```

2. Reload:
```sh
docker kill --signal SIGHUP pipelock
```

3. Test from inside the agent container:
```sh
echo '{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"Employee NI: AB123456C"}]}}' \
  | pipelock mcp scan --config /etc/pipelock/pipelock.yaml --json | jq .
```

4. Verify the audit log shows the block:
```sh
docker logs pipelock | jq 'select(.event == "blocked")' | tail -5
```
