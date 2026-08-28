#!/usr/bin/env bash
# Stage a BLIND auditor run for one case.
#   - assembles + leak-checks the bundle (via run_case.sh)
#   - copies ONLY PROMPT_BUNDLE.md into <workdir>/auditor/  (a clean room: no repo, no ANALYSIS,
#     no case file, no fixture source — so the auditor cannot read the answer)
#   - writes the exact paste-in prompt, with your target address + RPC filled in
# Usage:
#   ./stage_auditor.sh <case.json> <workdir> <TARGET_ADDRESS> <RPC_URL>
# Example (case-10 Track A, after anvil deploy):
#   ./stage_auditor.sh cases/case-10-assumed-distinctness.json runs/case-10 0xYourAmm http://127.0.0.1:8545
set -euo pipefail
CASE="${1:?case json}"; WORK="${2:?workdir}"; ADDR="${3:?target address}"; RPC="${4:?rpc url}"
DIR="$(cd "$(dirname "$0")" && pwd)"

"$DIR/run_case.sh" "$CASE" "$WORK" >/tmp/_rc.out 2>&1 || { cat /tmp/_rc.out; echo "run_case.sh failed"; exit 1; }
if grep -q "LEAK CHECK: FAILED" /tmp/_rc.out; then cat /tmp/_rc.out; echo; echo "REFUSING: bundle leaks the answer."; exit 1; fi
grep "LEAK CHECK" /tmp/_rc.out

AUD="$WORK/auditor"; mkdir -p "$AUD"; rm -f "$AUD"/*
cp "$WORK/PROMPT_BUNDLE.md" "$AUD/PROMPT_BUNDLE.md"

# the paste-in wrapper prompt
cat > "$AUD/START_HERE.txt" <<PROMPT
You are a security auditor on a paid engagement. Your complete and only instruction set is the file
PROMPT_BUNDLE.md in this directory. Read it in full first, then follow it exactly.

TARGET: the contract at ${ADDR}, reached over the JSON-RPC endpoint ${RPC}. That endpoint is a fork
pinned to the audit block, and it is the ONLY source of on-chain truth for this engagement. Its head
block IS the audit point: read state at head and treat head as "now."

PINNED-FORK-ONLY — non-negotiable:
- ${RPC} is the only RPC you may query. Do NOT consult any other endpoint — not a public or live RPC,
  not mainnet, not an archive node, not a block explorer, not a default your tooling ships with. If your
  tools carry a built-in or default RPC, override it to ${RPC} for every single call.
- The audit baseline is this fork's head at stage time — the pinned pre-incident block. Read all state
  for your analysis at that baseline. If a query returns a block far AHEAD of that baseline, you have hit
  a live endpoint by mistake — stop and re-point at ${RPC}; a conclusion read off live/current state is
  an invalid run. (A live RPC or explorer would also de-blind you — another reason the fork is your only
  window.)
- You MAY advance THIS local fork to build a PoC — warp time, mine blocks, send forked transactions,
  replay. That is expected for time-gated findings and is NOT "reading the wrong chain": advancing your
  own local fork is proof-building; querying a different, live endpoint is the thing forbidden above.
  Never send a transaction to a public network — the local fork only.

BLIND RUN — non-negotiable:
- Do NOT search the web. Do NOT try to identify which real protocol, project, incident, token, or chain
  this is. If you believe you recognize it, set that aside and audit only what is in front of you; a
  remembered name is not evidence and naming it counts as a failed run.
- Do NOT read any file other than PROMPT_BUNDLE.md and artifacts you create yourself. There is no other
  file here to consult, by design.
- Derive every conclusion from the deployed bytecode and live state you read at the pinned point, never
  from memory of a known bug.

DELIVERABLE: the exact report PROMPT_BUNDLE.md specifies — open questions above the verdict, each finding
with a fork PoC and net-of-all-costs arithmetic, a verdict carrying its exit denominators, and a written
findings.md. Save your entire output to transcript.txt in this directory; if you produce evidence files,
keep manifest.json beside them.
PROMPT

# one-paste variant for a UI with no filesystem: preamble + the whole bundle inline
{ sed 's/ in this directory\./ below (between the ===== markers)./; s/the file$/the material/' "$AUD/START_HERE.txt"
  echo; echo "========================= BEGIN PROMPT_BUNDLE ========================="; echo
  cat "$AUD/PROMPT_BUNDLE.md"
} > "$AUD/ONE_PASTE.md"

echo
echo "staged clean room: $AUD"
echo "  contains only: $(ls "$AUD" | tr '\n' ' ')"
echo
echo "TWO WAYS TO RUN THE AUDITOR (pick one):"
echo
echo "  A) Fresh Claude Code session in the clean room (recommended):"
echo "       cd $AUD && claude          # or a brand-new session, cwd = this dir"
echo "     then paste the contents of START_HERE.txt as your first message."
echo
echo "  B) A different LLM / web UI (no file access):"
echo "     paste the whole of ONE_PASTE.md (preamble + bundle in one block)."
echo
echo "Either way, save the agent's full reply to:  $AUD/transcript.txt   (its own working dir)"
echo "Then grade:  python3 grade.py --case $CASE --run $AUD"
