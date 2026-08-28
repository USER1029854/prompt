#!/usr/bin/env bash
# One-shot: deploy the case-10 fixture on your local anvil and seed it.
# No copy-paste of addresses — it captures them and prints the next command.
# Prereqs: `anvil` already running in another terminal (see below), and foundry on PATH.
set -euo pipefail

RPC="${RPC:-http://127.0.0.1:8545}"
PK="${PK:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"       # anvil acct#0 = victim
ATT_PK="${ATT_PK:-0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d}" # anvil acct#1 = attacker
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/MiniAmm.sol"

command -v forge >/dev/null || { echo "ERROR: foundry not found. Install: curl -L https://foundry.paradigm.xyz | bash && foundryup"; exit 1; }
command -v cast  >/dev/null || { echo "ERROR: 'cast' not found (part of foundry)."; exit 1; }
cast block-number --rpc-url "$RPC" >/dev/null 2>&1 || { echo "ERROR: no chain at $RPC. In another terminal run:  anvil"; exit 1; }

# Deploy one contract and echo its address. --constructor-args is GREEDY (it eats every following
# token, including flags), so it MUST come last; putting it before --broadcast is the classic
# "expected 1 but got 3" error. We parse the stable "Deployed to:" line, not --json, so a real forge
# error is shown instead of hidden behind a parse failure.
create() {
  local id="$1"; shift
  local out addr
  if ! out=$(forge create "$id" --rpc-url "$RPC" --private-key "$PK" --broadcast "$@" 2>&1); then
    echo "ERROR: forge create $id failed:" >&2; echo "$out" >&2; exit 1
  fi
  addr=$(printf '%s\n' "$out" | sed -n 's/.*Deployed to: *\(0x[0-9a-fA-F]\{40\}\).*/\1/p' | head -1)
  [ -n "$addr" ] || { echo "ERROR: could not find a deployed address for $id in:" >&2; echo "$out" >&2; exit 1; }
  echo "$addr"
}

echo "deploying fixture from $SRC ..."
TOKEN=$(create "$SRC:MockToken" --constructor-args "T")   # constructor-args LAST
AMM=$(create "$SRC:MiniAmm")
[ -n "$TOKEN" ] && [ -n "$AMM" ] || { echo "ERROR: deploy produced no address (see forge output above)." >&2; exit 1; }

VICTIM=$(cast wallet address --private-key "$PK")
ATTACKER=$(cast wallet address --private-key "$ATT_PK")
V=1000000000000000000000   # 1000e18 — the victim liquidity (the money to be taken)
A=100000000000000000000    #  100e18 — the attacker's honest stake
MAX=$(cast max-uint)

echo "seeding (victim 1000, attacker 100) ..."
cast send "$TOKEN" "mint(address,uint256)"    "$VICTIM"   "$V"   --rpc-url "$RPC" --private-key "$PK"     >/dev/null
cast send "$TOKEN" "mint(address,uint256)"    "$ATTACKER" "$A"   --rpc-url "$RPC" --private-key "$PK"     >/dev/null
cast send "$TOKEN" "approve(address,uint256)" "$AMM"      "$MAX" --rpc-url "$RPC" --private-key "$PK"     >/dev/null
cast send "$TOKEN" "approve(address,uint256)" "$AMM"      "$MAX" --rpc-url "$RPC" --private-key "$ATT_PK" >/dev/null
cast send "$AMM"   "deposit(address,uint256)" "$TOKEN"    "$V"   --rpc-url "$RPC" --private-key "$PK"     >/dev/null
cast send "$AMM"   "deposit(address,uint256)" "$TOKEN"    "$A"   --rpc-url "$RPC" --private-key "$ATT_PK" >/dev/null

echo
echo "  TOKEN = $TOKEN"
echo "  AMM   = $AMM   <- the audit target"
echo "  pool holds 1100 T; attacker honest claim 100 T; open door is swap(T,T,...)"
echo
echo "NEXT — stage the blind auditor run (copy this one line):"
echo
echo "  ( cd \"$(cd "$DIR/.." && pwd)\" && ./stage_auditor.sh cases/case-10-assumed-distinctness.json runs/case-10 $AMM $RPC )"
