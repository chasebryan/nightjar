#!/usr/bin/env bash
# Advertise a BLE beacon that carries a payload, forever.
# Needs: pip install 'nightjar[tx]'
set -euo pipefail

# 8 bytes: "nj" + CRLF + "hack" + CRLF
exec nightjar send ble:// \
  --name nightjar-post \
  --payload-hex "6e6a0d0a6861636b0d0a" \
  --company-id 0xFFFF
