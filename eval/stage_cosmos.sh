#!/usr/bin/env bash
# Blind-stage a Cosmos / app-chain case (no anvil; the target is a chain+height+binary, not an address).
# Usage:
#   ./stage_cosmos.sh <case.json> <workdir> <CHAIN_ID> <HEIGHT> <BINARY_VERSION> <LIVE_ENDPOINT>
# Example (ONE line — the args after <workdir> are CHAIN_ID HEIGHT "BINARY" ENDPOINT):
#   ./stage_cosmos.sh cases/case-13-batched-message-overwrite.json runs/case-13d mayachain-mainnet-v1 17977941 "mayanode v1.132.0 (git ff018576a6ea)" https://mayanode.mayachain.info
set -euo pipefail
[ $# -lt 6 ] && { echo "usage: stage_cosmos.sh <case.json> <workdir> <CHAIN_ID> <HEIGHT> <BINARY_VERSION> <LIVE_ENDPOINT>"; echo "(got $# args — a mangled multi-line paste? run it as ONE line)"; exit 2; }
CASE="${1:?case}"; WORK="${2:?workdir}"; CHAIN="${3:?chain id}"; H="${4:?height}"; BIN="${5:?binary version}"; EP="${6:?live endpoint}"
DIR="$(cd "$(dirname "$0")" && pwd)"
"$DIR/run_case.sh" "$CASE" "$WORK" >/tmp/_rc.out 2>&1 || { cat /tmp/_rc.out; exit 1; }
grep -q "LEAK CHECK: FAILED" /tmp/_rc.out && { cat /tmp/_rc.out; echo "REFUSING: bundle leaks the answer."; exit 1; }
grep "LEAK CHECK" /tmp/_rc.out
AUD="$WORK/auditor"; mkdir -p "$AUD"; rm -f "$AUD"/*; cp "$WORK/PROMPT_BUNDLE.md" "$AUD/"
cat > "$AUD/START_HERE.txt" <<PROMPT
You are a security auditor on a paid engagement. Your complete and only instruction set is the file
PROMPT_BUNDLE.md in this directory (CORE method + substrate module + target brief). Read it fully, then
follow it exactly.

TARGET — a Cosmos-SDK app-chain, NOT an EVM contract (there is no address to fork):
- chain id:      ${CHAIN}
- pinned height: ${H}
- binary:        ${BIN}  (bind source to this deployed binary by its reproducible build / version tag
                 before trusting any source — a repo is a claim, not the deployment)
- live reads:    query state AT height=${H} via the chain's own endpoints, starting at ${EP}
- PoC path:      there is no anvil fork. Prove findings with the chain's own Go test harness at the pinned
                 version (submit the message sequence, assert the broken invariant) or a replay at the
                 pinned height — per CORE 6 and the module. Inability to build it is a first-hour fact.

PINNED-HEIGHT-ONLY — non-negotiable (a halted-then-patched chain's live head is NOT the audit target):
- Read ALL state at height=${H} — append ?height=${H} to REST queries (or the equivalent height flag).
  This chain may have halted after the incident and resumed on a later, PATCHED version, so the live head
  is far ahead of ${H} and is a different, fixed chain state. A conclusion read off the live head is an
  invalid run.
- Bind source to the binary/version running AT height=${H}, NOT the version the node advertises now. If
  the node reports a version ahead of the pinned height, that later version is (or contains) the fix —
  auditing it yields a false "already patched." Confirm which version-gated code path actually executed
  at ${H}; that is the code under audit.
- You MAY build and run a Go harness at the pinned version to prove a finding — that is proof-building,
  not "reading the wrong chain."

BLIND RUN — non-negotiable:
- Do NOT search the web or the incident. Derive from the deployed artifact and live state at the pinned
  height, never from memory of a known bug.
- Because the source is a public named repo you may recognize the project. Set that aside: a remembered
  incident is not evidence, and naming it before on-chain/code evidence is a failed run.

DELIVERABLE: the report PROMPT_BUNDLE.md specifies — open questions above the verdict, findings with a PoC
(go test / replay) and net-of-costs arithmetic, a verdict with exit denominators, and findings.md. Save
your entire output to transcript.txt in this directory.
PROMPT
echo "staged clean room: $AUD  ($(ls "$AUD" | tr '\n' ' '))"
echo "run auditor:  cd $AUD && codex   # paste START_HERE.txt"
echo "grade:        python3 grade.py --case $CASE --run $AUD"
