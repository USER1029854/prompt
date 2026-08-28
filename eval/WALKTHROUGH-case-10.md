# Running case-10 end to end

Two tracks. **Track A** validates the whole pipeline in ~15 minutes against a local fixture and gives a
real read on whether CORE's Lens E mirror fires. **Track B** is the historical measurement. Do A first —
if the pipeline is broken you want to find out before spending a day on an archive node.

Why A exists: case-10's origin is on a non-EVM VM with no module and no anvil-grade fork tooling, so the
literal target in `answer_for_grader_only` is not runnable the way case-03 or case-06 are. Track A keeps
the *defect shape* exactly and swaps the substrate — which is the whole claim the case is testing, since
the class is substrate-free.

---

## Step 0 — prove the harness works (30 seconds)

```bash
cd eval
./run_case.sh cases/case-10-assumed-distinctness.json runs/case-10
```
Expect `LEAK CHECK: PASS`. Then look at what the auditor will receive — this is the one thing worth
checking by eye every time:
```bash
cat runs/case-10/BRIEF.json
```
It must contain **only** `id`, `substrate_modules`, `blinded_brief`. If a `class` or `note` field appears,
your `run_case.sh` predates the whitelist fix and the auditor is being handed the answer.

---

## Track A — local fixture

### A1. Start a chain and deploy
```bash
anvil                                    # terminal 1, leave running
```
```bash
# terminal 2
export RPC=http://127.0.0.1:8545
export PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80   # anvil acct 0, public test key
export ATT_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d # anvil acct 1

forge create --rpc-url $RPC --private-key $PK eval/fixtures/MiniAmm.sol:MockToken --constructor-args "T"
forge create --rpc-url $RPC --private-key $PK eval/fixtures/MiniAmm.sol:MiniAmm
```
Record the two addresses as `$TOKEN` and `$AMM`.

### A2. Seed it so there is someone else's money to take
```bash
VICTIM=$(cast wallet address --private-key $PK)
ATTACKER=$(cast wallet address --private-key $ATT_PK)

# victim deposits 1000, attacker deposits 100
cast send $TOKEN "mint(address,uint256)" $VICTIM   1000ether --rpc-url $RP
