#!/usr/bin/env bash
# Knock on a TCP port ten times and read each reply.
set -euo pipefail

nightjar send tcp://127.0.0.1:9000 \
  --payload "knock" \
  --repeat 10 \
  --interval 0.5 \
  --framing len \
  --read \
  --timeout 3
