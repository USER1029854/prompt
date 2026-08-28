#!/usr/bin/env bash
# Blind-stage a REAL historical fork case (no local fixture). One command:
#   forks an archive RPC at <exploit_block - 1>, checks the target has code there,
#   then stages the clean-room bundle + prompt exactly like stage_auditor.sh.
#
# Usage:
#   ./stage_real.sh <case.json> <workdir> <ARCHIVE_RPC_URL> <EXPLOIT_BLOCK> <TARGET_ADDR>
# Example (fill from the grader answer + a block explorer for the incident):
#   ./stage_real.sh cases/case-03-guard-on-wrong-path.json runs/case-03 \
#       https://eth-mainnet.g.alchemy.com/v2/KEY 12345678 0xVaultAddr
#
# Needs foundry (anvil/cast). Leaves anvil running in the background; stop it with the printed kill line.
set -euo pipefail
[ $# -lt 5 ] && { echo "usage: stage_real.sh <case.json> <workdir> <ARCHIVE_RPC> <EXPLOIT_BLOCK> <TARGET_ADDR>"; echo "(got $# args — a mangled multi-line paste? run it as ONE line)"; exit 2; }
CASE="${1:?case json}"; WORK="${2:?workdir}"; RPC="${3:?archive rpc url}"; BLOCK="${4:?exploit block number}"; ADDR="${5:?target address}"
DIR="$(cd "$(dirname "$0")" && pwd)"
command -v anvil >/dev/null || { echo "ERROR: foundry not found (anvil/cast). https://getfoundry.sh"; exit 1; }
command -v cast  >/dev/null || { echo "ERROR: 'cast' not found."; exit 1; }
case "$BLOCK" in ''|*[!0-9]*) echo "ERROR: EXPLOIT_BLOCK must be a number, got '$BLOCK'"; exit 1;; esac
FORK_AT=$((BLOCK - 1))                       # pin ONE block before the exploit
LOCAL=http://127.0.0.1:8545
mkdir -p "$WORK"

# already something on :8545? refuse rather than fork on top of a stale chain
if cast block-number --rpc-url "$LOCAL" >/dev/null 2>&1; then
  echo "NOTE: something is already serving $LOCAL (probably an anvil from an earlier case)."
  echo "      A stale chain would fork the WRONG state, so stop it first, then re-run this command:"
  echo "        pkill anvil        # or Ctrl-C in the terminal running it, or: kill \$(lsof -ti:8545)"
  exit 1
fi

echo "forking $RPC at block $FORK_AT (exploit block $BLOCK minus 1) ..."
nohup anvil --fork-url "$RPC" --fork-block-number "$FORK_AT" >"$WORK/anvil.log" 2>&1 &
echo $! > "$WORK/anvil.pid"

# wait for the fork to come up
for i in $(seq 1 30); do cast block-number --rpc-url "$LOCAL" >/dev/null 2>&1 && break; sleep 1; done
cast block-number --rpc-url "$LOCAL" >/dev/null 2>&1 || { echo "ERROR: fork did not start. See $WORK/anvil.log:"; tail -20 "$WORK/anvil.log"; exit 1; }
HEIGHT=$(cast block-number --rpc-url "$LOCAL")
echo "  fork live at height $HEIGHT"

# the target must actually have bytecode at this block, or the auditor is auditing an empty address
CODE=$(cast code "$ADDR" --rpc-url "$LOCAL" 2>/dev/null || echo 0x)
if [ "$CODE" = "0x" ] || [ -z "$CODE" ]; then
  echo "ERROR: target $ADDR has NO code at block $FORK_AT — wrong address, wrong chain, or not deployed yet." >&2
  echo "       (stop the fork: kill \$(cat $WORK/anvil.pid))" >&2; exit 1
fi
echo "  target $ADDR has ${#CODE} hex chars of bytecode — good"

"$DIR/stage_auditor.sh" "$CASE" "$WORK" "$ADDR" "$LOCAL"
echo
echo "when done auditing, stop the fork:  kill \$(cat $WORK/anvil.pid)"
