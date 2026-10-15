#!/usr/bin/env bash
# A two-way loop: serve on 9000, then talk to it, then stop the server.
set -euo pipefail

nightjar serve --tcp 9000 --reply "ack" --out received.jsonl &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null || true' EXIT

sleep 0.5

for i in 1 2 3; do
  nightjar send tcp://127.0.0.1:9000 --payload "tick $i" --read
done

sleep 0.3
echo
echo "--- received.jsonl ---"
cat received.jsonl
