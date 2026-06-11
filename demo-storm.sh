#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# demo-storm.sh — run this ON CAMERA, AFTER you've deposited on the frontend.
#
# It does the two on-chain steps that sit between "deposit" and "claim":
#   1. A storm swap  → the hook skims a VRS-scaled fee into the YieldBuffer
#   2. Distribution  → closes the current epoch so your deposit becomes claimable
#
# In production these are a trader's swap + the Reactive RSC's automatic payout.
# Make sure VRS is high (push 85 earlier in the demo) so the fee is meaningful.
# ─────────────────────────────────────────────────────────────────────────────
set -e
cd "$(dirname "$0")"
set -o allexport; source .env; set +o allexport
export SWAP_ROUTER=0x9b6b46e2c869aa39918db7f52f5557fe577b6eee

LP=0x69322eC2B35D73e2014a0B015160c1158f07C793   # your demo wallet

echo ""
echo "==> 1/2  Storm swap (hook skims a fee into the buffer)..."
forge script script/StormSwap.s.sol:StormSwap \
  --rpc-url "$SEPOLIA_RPC_URL" --broadcast --private-key "$PRIVATE_KEY" \
  2>&1 | grep -E "Storm swap|ONCHAIN" || true

echo ""
echo "==> 2/2  Storm passes — triggering distribution..."
cast send "$YIELD_BUFFER" "triggerDistribution()" \
  --rpc-url "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY" \
  2>&1 | grep -E "^status"

PREV=$(($(cast call "$YIELD_BUFFER" "currentEpoch()(uint256)" --rpc-url "$SEPOLIA_RPC_URL") - 1))
echo ""
echo "==> Done. Your claimable for epoch $PREV:"
cast call "$YIELD_BUFFER" "previewClaim(address,uint256)(uint256,uint256)" "$LP" "$PREV" --rpc-url "$SEPOLIA_RPC_URL"
echo ""
echo "Now refresh the Buffer page and click Claim."
