#!/bin/sh
# Redeploys PolyLend on anvil, rebuilds the testnet webapp with the new
# address, and restarts the testnet backend so it re-reads the deployment
# JSON. Idempotent: the Foundry script no-ops if the recorded address
# still has code, so this is safe to run repeatedly.
set -eu

cd "$(dirname "$0")/.."

JSON=./data/testnet-deployments/testnet.json

echo "==> Running testnet-deploy"
docker compose up testnet-deploy

if [ ! -f "$JSON" ]; then
  echo "ERROR: $JSON not found after testnet-deploy" >&2
  exit 1
fi

# Parse the address from the JSON without requiring jq or node on the host
ADDR=$(sed -n 's/.*"polylend":[[:space:]]*"\(0x[a-fA-F0-9]\+\)".*/\1/p' "$JSON" | head -1)
if [ -z "$ADDR" ]; then
  echo "ERROR: could not parse 'polylend' address from $JSON" >&2
  exit 1
fi
echo "==> Resolved TESTNET_POLYLEND_ADDRESS=$ADDR"

echo "==> Building web-testnet-build with the new address"
TESTNET_POLYLEND_ADDRESS="$ADDR" docker compose build web-testnet-build

echo "==> Recreating web-testnet-build (one-shot, populates web_testnet_dist volume)"
TESTNET_POLYLEND_ADDRESS="$ADDR" docker compose up -d --force-recreate --no-deps web-testnet-build
docker wait infra-web-testnet-build-1 >/dev/null || true

echo "==> Restarting caddy to serve the new bundle"
docker compose restart caddy

echo "==> Restarting testnet backend services (they re-read the deployment JSON)"
docker compose restart listener-testnet api-testnet

echo
echo "==> Done. https://testnet.polylend.com → PolyLend at $ADDR"
