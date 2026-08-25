# Why these keep getting past you

This document is the reasoning behind the rewrite. It is **not** part of the audit prompt and must
never be given to an auditing agent — it names specific incidents, and an auditor that has read it
will hunt for those incidents instead of thinking. Keep it on the reviewer's side of the wall.

---

## 1. The calibration set

Eight incidents. Six you named, two found while checking whether your six were representative.
I stripped each to its structural shape, discarding the protocol, the language, and the chain.

| Incident | Where the defect lived | Structural shape |
|---|---|---|
| Cross-chain trade-account drain (Cosmos app-chain, Aug 2026) | Between the observation/voting subsystem and the slashing subsystem | Handler returned an error; caller logged it and continued. Partial state survived the failure meant to prevent it. Amplified by an empty pool and a stale versioned code branch. |
| Governance capture of a vault DAO (EVM, 2026) | Between a governance framework and a treasury framework | The delayed party could reconfigure its own delay. Voting token float was **0.5352 tokens**. |
| LP-manager vault drained via spot price (EVM, 2026) | Between the manager path and the user path | A TWAP guard existed in the codebase — wired to `rebalance()`, absent from `mint()`/`burn()`. |
| Bridge credited on a forged CCTP message (EVM, Aug 2026) | Between an attester's semantics and the bridge's credit semantics | Signature was genuine. The *message* was attacker-authored. Envelope validated; economics not. |
| Shared-framework precompile drain (Cosmos EVM, Jan + Aug 2026) | Between the EVM execution model and the SDK bank state | State written in a nested call context was not reflected in the outer context → same balance spent twice in one tx. |
| Bridge denom-registry poisoning (Cosmos↔EVM, May 2026) | Between two naming systems for "the same asset" | A permissionless registration function let an attacker bind a fabricated denom to a real custody contract. |
| ERC20 bridge, non-EVM side (2026) | Between two chains, one of which nobody read | Reviewers audited the side written in the language they read. |
| Perp/vault price manipulated via read-only reentrancy (EVM, 2025) | Between a writer and an external reader | A view function returned mid-transaction state to a contract that priced off it. |

**Eight for eight, the defect lived at a seam — a boundary where one system restates a fact
produced by another.** Not one of them was a bug inside a function that a line-by-line read of
that function would reveal. Every individual component was defensible in isolation. That is why
they survived audits: audits read components.

Two of the eight also share a second property worth its own line. The governance capture turned on
a live number — a voting token with a total supply of **0.5352** — and the app-chain drain turned
on two live numbers, a pool with ~0.11 units of asset depth and a reserve holding 168k against a
49.45M draw. In all three cases **a single state read, costing one RPC call, would have exposed the
condition the attack required**, months before the attack. Nobody made the call, because nobody had
a step that said "the guard is a number; go read the number."

## 2. What your current prompt does well

Worth being explicit, because the rewrite keeps all of it:

- Evidence discipline (`Only claim what you read`, the manifest, `UNVERIFIED` on unenumerated sets).
  This is stronger than most professional methodology and it is the reason your reports are
  trustworthy. Kept verbatim in spirit.
- `The deployment is the system` — repo is a claim, chain is the fact. Correct and rare.
- Forced enumeration of factories/registries from creation events rather than sampling. Correct.
- The five lists that survive every carry-forward. The single best idea in the document; the
  rewrite promotes it from a context-management note to the spine of the whole method.
- Execution gating (fork + PoC or an explicit `UNPROVEN` label). Correct.
- The Phase 9 "argue the other side" pass. Correct and almost never done.

The problem is not rigour. Your prompt is more rigorous than the audits that missed these bugs.
The problem is **what the rigour is pointed at.**

## 3. Seven structural defects, each mapped to something that got through

### 3.1 It is contract-centric, and the bugs are not in contracts

The unit of work throughout is the contract: inventory contracts, read contracts, enumerate a
contract's selectors, diff a contract against its repo. Six of the eight defects above cannot be
expressed as a property of any single contract. They are properties of a *relationship*.

The rewrite makes the seam a first-class object with its own register, its own enumeration
obligation, and its own four-question sweep. A component that touches no seam gets a cheap read;
a seam gets the expensive treatment regardless of which component it sits between.

### 3.2 It never prices a guard

The prompt asks whether a guard *exists*. It never asks what defeating it *costs*. Yet in the
calibration set the guards mostly existed:

- Governance vote → existed, cost **$2,000** to acquire 90.66% of.
- 7-day timelock → existed, cost one proposal to set to zero.
- TWAP deviation check → existed, on a path the attacker didn't need.
- Cryptographic attestation → existed, and was *correctly issued* over attacker-authored content.
- Reserve-covers-subsidy → existed as an implicit assumption, cost nothing because the reserve was
  0.3% of the draw.
- Canonical-asset registry → existed, cost one permissionless call to poison.

"Guarded" is not a finding-killer. "Guarded, and defeating the guard costs more than the guard
protects" is. The rewrite adds a **guard register** where every guard carries a computed price in
dollars, sourced from live state, and a guard whose price is below what it protects is a finding on
its own — before you have any exploit path at all.

### 3.3 The reachability gate excludes two of the eight by construction

Your gate reads: *"The exploit runs from an address holding no role, ownership, whitelist entry, or
operator status"* and *"Holding a real position, keeping capital at risk across blocks... fail."*

Applied literally:

- The governance capture is **out of scope** — at execution time the attacker held a majority of
  the voting power, which is a role. An auditor following the gate files it as "a privileged party
  misusing powers they hold." It cost $2,000 to become that privileged party.
- The forged-message bridge attack is **out of scope** — the attacker seeded a message 24 days
  before firing, which reads as "keeping something at risk across blocks."

Both readings are wrong, and both are what the text says. The gate is measuring the wrong things.
The right questions are:

- Not "is the attacker privileged?" but **"what does the privilege cost to acquire?"**
- Not "is it atomic?" but **"how much unrecoverable capital is at risk?"** Waiting is free.
  Precomputation is free. Pre-registration is free. Deploying a helper is free. A seeded message
  sitting for a month costs gas and patience, neither of which is capital at risk.

The rewrite replaces `Unprivileged` with **Acquirable** (privilege permitted, priced) and redefines
`Cheap` in terms of capital at risk rather than time or atomicity.

### 3.4 It has no atomicity axis

"What happens when something fails halfway" is item 4 of 7 in an appendix. It is the direct cause
of two of the eight — the app-chain drain (handler error logged, state kept) and the shared-framework
precompile drain (nested-context writes not reflected outward, same balance spent twice).

This deserves to be a top-level sweep because it is *mechanically enumerable*: list every site where
value-bearing state is written near something that can fail, list every place an error is discarded,
and state what the atomic unit actually is on this substrate. That last one matters enormously and
differs per substrate — the EVM transaction, the Cosmos *message* inside a batched transaction, the
Solana instruction inside a transaction. Code written by someone thinking in the wrong unit is the
bug.

### 3.5 It has no concept of asymmetric attention

The bugs are in the code nobody looks at, and which code that is, is predictable:

- the other chain's side of a bridge (one of eight, exactly this)
- the framework/dependency rather than the app (one of eight, and it recurred seven months later on
  three more chains)
- the older versioned branch of a function that has a newer one (a contributing bug in one of eight —
  the newer path capped the amount, the older path did not, and nobody audits `_v92` when `_v96` exists)
- migration, upgrade, and emergency paths
- `EndBlock`/cron/keeper-triggered code with no external caller
- the path guarded by a role, dismissed as privileged without pricing the role

The rewrite adds an **attention-inversion sweep**: rank the surface by how much scrutiny it has
already received and spend inversely. This is the cheapest high-yield step in the whole method and
nothing in your current prompt asks for it.

### 3.6 It treats dependencies as a diff target, not as a live advisory surface

Your Integrity step diffs shared building blocks against upstream and checks "what landed since."
Good, but framed as a tampering check. The dominant real case is different: **a published,
patched advisory in a shared dependency, unapplied at this deployment.**

The precompile bug is the proof. It cost one chain ~$7M in January. The advisory was public. In
August it hit three more chains running the same unpatched module; fifteen chains were found running
the flawed code. The single highest-probability finding in any system is a **known** bug the
deployment hasn't taken. That check takes twenty minutes: pin every dependency's exact version,
pull its advisory list, confirm each fix is present *in the running artifact*.

Your prompt gets close ("Matching a version with a known bug is a finding") but buries it inside
Integrity and never demands a version-pinned dependency list as an artifact.

### 3.7 The `UNPROVEN` cap pushes out exactly the expensive findings

"At most two `UNPROVEN` findings total" creates a quiet incentive: the atomic single-transaction
exploits are easy to PoC and the multi-day compositional ones are not, so under pressure the
compositional ones get demoted to open questions. Those are the ones paying seven figures.

The rewrite dissolves the tension technically rather than by raising the cap: **a finding blocked
only by elapsed time is not unproven, it is unwarped.** Fork state, jump the clock or the height,
run it. A six-day governance delay and a 24-day seeded message are both provable on a fork in
seconds. `UNPROVEN` should be reserved for a link you cannot construct *at all*, not for one you
declined to fast-forward.

## 4. On your "dead run" idea

You asked whether telling the auditor *"there is a bug in here, find it"* would make it try harder.

**Yes, and that is the problem.** It converts a precision task into a recall task. An agent told
that a bug exists will produce one. It will take the weakest thing it noticed — an unbounded admin
setter, a missing zero-check on an oracle input, a rounding direction — and dress it in severity
language until it clears the bar. You will get a full report, high confidence, and nothing real; and
because the report is well-evidenced in form, it is expensive to disbelieve. Repeat that on real
engagements and you train yourself to discount your own tool, which is worse than the original
problem.

The intuition underneath it is nevertheless correct: **an agent that expects to find nothing
under-invests.** The fix is to make the effort mandatory without making the conclusion mandatory.
Three mechanisms in the rewrite do that:

1. **Denominators.** Every sweep produces a count first and a disposition per item second: N seams,
   N guards, N defenses, N failure sites, N degenerate quantities, N surfaces. You cannot skate an
   enumeration you had to number. The floor on effort is structural, not motivational.
2. **A kill quota.** Each lens requires a minimum number of written attack hypotheses, *each killed
   with a cited line of code or promoted*. Killing costs as much thought as finding, and its output
   is honest. This is the piece that actually replaces "there is a bug in here": the agent spends
   the same energy, and what it hands back is a kill list rather than a confabulation.
3. **The Null Report.** A clean verdict is incomplete unless it ships with the three places the
   missed bug most likely lives, ranked by cost-if-wrong, each with the specific action that would
   settle it. It is much harder to hand-wave a clean verdict when the clean verdict has a mandatory
   section titled "where I would bet I am wrong."

And state the honest prior explicitly in the prompt: most systems you audit have a live exploitable
path, because you are pointed at systems worth exploiting — but *this* one may not, and inventing
one is a worse failure than missing one. That is a truthful motivator. "There is definitely a bug"
is not, and the agent's calibration is downstream of whether you lie to it.

## 5. On testing against a historical build

Right instinct, and worth building properly — `eval/` is that. Three things determine whether it
tells you anything:

**Contamination.** Any famous incident is in the model's weights and one search away. A run that
outputs the right answer may have retrieved it rather than derived it, and you cannot tell from the
answer. Three controls: strip identifying metadata from the target; weight the suite toward obscure
and recent incidents; and — the important one — **score the path, not the answer.**

**Score `must_reach`, not the finding.** Each case names the intermediate observations that
constitute having actually traversed the path: *"read the live total supply of the voting token and
recorded that it is under 1"*, *"listed both call sites of the price read and noted the deviation
check on only one"*, *"identified that the destination acts on fields not covered by the
attestation."* An auditor that makes those observations will find the same class on a protocol it
has never heard of. An auditor that names the incident without them has recalled, not reasoned.
This is the only measurement that predicts performance on the next one, which is the thing you
actually want to know.

**Run clean controls.** Without unexploited targets in the suite you will tune toward a prompt that
finds something everywhere. Measure false positives per clean run explicitly; a prompt that scores
100% recall and reports two criticals per clean target is worse than useless. Track both numbers or
neither.

Practical note: pin the fork one block *before* the exploit and hand over nothing else. If the
target is an app-chain, that means a height and a binary version, not a contract address.

## 6. What actually changed

| | Old | New |
|---|---|---|
| Primary object | Contract | **Seam** |
| Guards | Existence checked | **Priced in dollars from live state** |
| Privilege | Disqualifies a finding | **Priced; acquirable privilege is in scope** |
| Cheapness | Atomic, no cross-block | **Capital at risk; time and precomputation are free** |
| Partial failure | Appendix item 4/7 | **Top-level sweep with an enumerated site list** |
| Attention | Not modelled | **Inverted deliberately; least-read surface first** |
| Dependencies | Diffed for tampering | **Version-pinned, advisory-checked against the running artifact** |
| Effort | Implicit | **Denominators + kill quota + Null Report** |
| Slow exploits | Demoted under an `UNPROVEN` cap | **Warped on a fork and proven** |
| Structure | 10 phases + a 7-item appendix | **5 passes + 6 lenses + a 9-register ledger on disk** |
| Substrate | EVM assumptions in the core | **Core is substrate-free; mechanics live in modules** |
| Self-measurement | None | **`eval/` with path-scored historical cases and clean controls** |

## 7. The one-line version

You were auditing components and asking whether guards exist. The money leaves at the joints
between components, through guards that exist and are cheap. Point the same rigour at the joints,
and put a price on every guard.
