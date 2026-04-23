#!/bin/sh
# Wrapper that compensates for --state / --state-interval being non-functional in
# current foundry releases. Persistence is driven via anvil_dumpState /
# anvil_loadState RPC calls instead.

set -eu

STATE_FILE="${STATE_FILE:-/data/anvil-state.json}"
DUMP_INTERVAL_SECS="${DUMP_INTERVAL_SECS:-600}"
ENDPOINT="http://localhost:8545"

log() { echo "[anvil-entrypoint] $*"; }

anvil \
  --fork-url "$RPC_URL" \
  --host 0.0.0.0 \
  --port 8545 \
  --chain-id 31337 \
  --block-time 2 \
  &
ANVIL_PID=$!

dump_state() {
  if cast rpc anvil_dumpState --rpc-url "$ENDPOINT" 2>/dev/null | tr -d '"' >"${STATE_FILE}.tmp"; then
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
    return 0
  fi
  rm -f "${STATE_FILE}.tmp"
  return 1
}

shutdown() {
  log "signal received, dumping final state"
  if dump_state; then
    log "final state dumped to $STATE_FILE"
  else
    log "WARNING: final dump failed"
  fi
  kill -TERM "$ANVIL_PID" 2>/dev/null || true
  wait "$ANVIL_PID" || true
  exit 0
}
trap shutdown TERM INT

until cast chain-id --rpc-url "$ENDPOINT" >/dev/null 2>&1; do
  sleep 1
done
log "anvil ready"

if [ -s "$STATE_FILE" ]; then
  log "loading state from $STATE_FILE"
  if cast rpc anvil_loadState "$(cat "$STATE_FILE")" --rpc-url "$ENDPOINT" >/dev/null 2>&1; then
    log "state loaded"
  else
    log "WARNING: state load failed, continuing with fresh fork"
  fi
fi

(
  while true; do
    sleep "$DUMP_INTERVAL_SECS"
    if dump_state; then
      log "state dumped at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    else
      log "WARNING: periodic dump failed"
    fi
  done
) &

wait "$ANVIL_PID"
