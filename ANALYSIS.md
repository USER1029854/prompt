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

---

# v2 — going to the ground

The user asked to rewrite from the ground up and remove anything that *suppresses detection* unless it
earns its place, and to widen the calibration set from the last ~6 months of on-chain logic exploits
(excluding key/credential compromise and social engineering, which are out of an on-chain audit's
scope — and which, notably, accounted for ~70% of 2026 losses; we are correctly *not* chasing them).

## Calibration set, widened

Added, all in-scope on-chain logic bugs, checked against SlowMist / DefiLlama / vendor postmortems:

| Incident | Where the defect lived | Structural shape (in v2 terms) |
|---|---|---|
| Concentrated-liquidity DEX, ~$223M (Move/Sui) | A shared liquidity-math helper | **Miscomputed number.** A bounds check used the wrong threshold for a 64-bit left-shift; the language aborts on overflow but shifts truncate *silently*. Mint huge liquidity for one token. |
| AMM vault, ~$128M (EVM) | `_upscaleArray` rounding | **Miscomputed + splitting + deferred settlement.** Floor division dropped a rate; 65+ micro-swaps in a constructor compounded it; batch internal balances let the books sit transiently unbalanced. |
| Lending market collateral (EVM) | Liquidation pricing | **Miscomputed/stale.** Liquidated at a price thousands× too low; reserves ate the shortfall (insolvency, small attacker gain). |
| Money market, cap bypass (EVM) | Supply-cap guard | **Unbounded / guard defeated.** Flash-acquired token to ignore caps and over-borrow. |
| ZK-gated withdrawals | Verifier config | **Forged.** Valid proof, unconstrained/misconfigured verifier → unauthorized withdrawals. |
| Perp settlement (Move/Sui) | Fee accounting | **Miscomputed.** Fee-accounting logic in settlement flows. |

Two lessons reshaped the core rather than just extending a list:

1. **The two largest pure-code losses of the year were boring core-math bugs** — a wrong shift-threshold
   and a floor-division. v1 filed precision/rounding under a sub-bullet of the composition lens. That is
   backwards: it is a *first-class production site of wrong numbers* and now has its own lens (C) and its
   own execution mandate (fuzz/prove the core math at edges, don't eyeball it). The single sharpest
   behavioral instruction added: **"the language aborts on overflow" is not proof the math is safe** —
   shifts and casts truncate silently, and the guard is the hand-rolled bound whose *threshold* is the
   bug, evaluated at its boundary.

2. **The unified spine.** Studying the wider set, every incident collapses to one sentence: *money
   leaves through an exit that trusts a wrong number, and a number goes wrong by being stale, forged,
   miscomputed, or unbounded.* v1 led with "seams," which captures stale/forged but reads past
   miscomputed/unbounded (the Cetus/Balancer family). v2 leads with **exits → the numbers they trust →
   the four ways a number is wrong**, with seams and arithmetic as the two production sites. This is a
   better net because it is exit-anchored: you start from the small closed set where money actually
   leaves and pull every trusted number backwards, so a miscomputed-but-not-cross-component bug (Cetus)
   can't hide from a seam-only search.

## Detection-suppressors removed or loosened

The user's core instruction: strip anything that stops detection. The honest ones in v1 (inherited from
the original prompt):

- **The `UNPROVEN` cap ("at most two total").** *Removed.* It was a reporting quota that, under
  pressure, pushed out exactly the hard-to-PoC *compositional* findings — the seven-figure ones. Its
  anti-confabulation purpose is served better by the kill-quota and evidence rules, which constrain
  *quality* without capping *quantity*. v2: report every substantiable path with an honest proof-state,
  ranked by severity, no numeric cap, and never demote a compositional finding to an open question to
  tidy the report.
- **The reachability gate's "live" clause as a dormant dumping ground.** *Sharpened.* v1 sent
  "reachable only after a flag flips" to the dormant register. But if the *attacker* can cause the
  precondition — acquirable governance, a permissionless call, a degenerate state already on-chain — it
  is live, not dormant. v2 says so explicitly, so a real, attacker-triggerable path can't be filed away
  as contingent.
- **Severity/scope anchored to attacker gain only.** *Widened.* v2 adds insolvency/value-destruction as
  a qualifying category (a mispriced liquidation that eats reserves while the attacker nets little is
  still critical), so a Moonwell-shape bug isn't discarded for failing the economic net-positive test.

Kept deliberately, because they defend against *false* positives (which the FP-controls in `eval/`
measure, and which are a detection failure in their own right): the evidence discipline, `UNVERIFIED` on
unenumerated sets, deployment-over-repo, byte-absence-is-not-evidence, the manifest. Removing these
wouldn't find more real bugs; it would drown the real ones in noise.

## Structural

- New spine: **exits × numbers × {stale, forged, miscomputed, unbounded}** (`CORE.md §1`).
- New first-class lens **C — miscomputation** (rounding direction, silent truncation, overflow/threshold
  at edges, splitting, deferred/transient settlement).
- New module **MOVE_SUI.md** (the largest in-scope venue of the period; Move's abort-on-overflow /
  silent-shift-truncation split is exactly the kind of per-language semantics an EVM-trained auditor
  misses).
- Modules gained per-language **arithmetic-semantics** sections, **deferred-settlement** (EVM), and
  **proof/verifier** seams (EVM, Solana, Bridge).
- `eval/` gained a precision/rounding case and a ZK-verifier case; the grader's matcher was rewritten
  (it had been doing character- not word-containment) and re-validated on positive, retrieval-only, and
  empty transcripts.

v1 is preserved as `CORE.v1.md` for diffing.

---

# v3 — the full-corpus rebuild

The user asked for exhaustiveness: harvest the whole last-6-months on-chain corpus (excluding
key/opsec/social/infra), let the data — not two headline hacks — drive the design, and add nothing that
isn't earned. Five parallel research agents classified the corpus (Feb–Aug 2026) from SlowMist (pages
1–11), DefiLlama, rekt, vendor postmortems, and per-substrate sweeps, each tagging every incident
against the v2 taxonomy and, crucially, flagging what *didn't* fit. The definitive harvest counted
**146 in-scope incidents with realized loss**, distributed:

| class | n | | class | n |
|---|---|---|---|---|
| AMOUNT-STALE (oracle / flash-loan price manip) | 37 | | TOKEN-SEMANTICS | 10 |
| AUTH-MISSING (broken access control) | 23 | | AUTH-ACQUIRABLE (governance capture) | 4 |
| AMOUNT-MISCOMPUTED (rounding/precision/sign) | 21 | | AMOUNT-UNBOUNDED (donation/first-depositor) | 4 |
| AUTH-FORGEABLE + Q3 mis-verification | 20 | | ATOMICITY | 3 |
| AMOUNT-FORGED (unbacked mint) | 16 | | IDENTITY | 2 |

Three MISFITS across all 146, and every one is already covered by v3: **Maya** (six chained flaws plus
neutralizing the protocol's own safety monitor → composition + Q3, the guard fed bad input to disable
it); **THORChain** (threshold-signature soundness → the TSS/consensus layer the Cosmos module now puts
in scope); **ATOHook** (a `rewards` slot colliding with a library's reentrancy-guard sentinel → the
storage slot-collision case in the EVM module and core Q7). No 147th shape appeared.

## What the corpus said

**The taxonomy held as a sink but mis-weighted the year.** ~90% of incidents classified cleanly into
authorization-or-amount. But three things were under-billed or missing, and the misfits clustered:

- **The dominant 2026 shape was "the verifier accepted what it should have rejected."** AUTH-FORGEABLE
  was ~32% of Jun–Aug incidents, but splitting it revealed most were not *forgery* — nothing was forged.
  The check passed while enforcing the wrong predicate or over the wrong scope: a ZK proof covering 32
  slots while settlement processed an attacker-controlled subset (Aztec Connect); a validator counting
  signature *slots* not valid signatures (Harmony); an out-of-range committee id yielding a zero BLS key
  that verified (Bonzo); an ERC-1271 check whose static-call success was never read (Gnosis Pay); a bond
  ledger tracking a *count* where identity was required (Lien). v2 had no first-class name for this.
- **Minting value against nothing was the most common bridge/L1 theft** (Verus, Syscoin, Secret,
  Harmony, Hyperbridge, Adshares, Oraichain, Allbridge). v2's spine said value *leaves* through an exit
  — but issuance *creates* value that leaves later on a legitimate path, so an exit-of-transfers audit
  walks past the mint.
- **Losses recur across a fleet.** The same bug fixed upstream but live on one instance (Allbridge on
  Solana), one shared dependency hitting many chains (the Cosmos-EVM precompile cluster; the
  Compound-fork exchange-rate class across Venus/dTRINITY), a fork that *removed* an upstream check
  (Secret's CW20-ICS20). A per-exit reading structurally can't see this.

## What changed in the core

The spine was rebuilt from "an exit trusts a wrong **number**" to **three questions asked of every
exit**, with the exit **redefined to include issuance**:

- **Q1 Authorization & identity** — is the right party acting on the real thing? (missing / forgeable /
  cheaply-acquirable auth; forged / collided / substituted identity). Identity is promoted from a
  cross-cutting enabler to a primary axis — in a whole class of thefts (Gravity denom poisoning, Raydium
  fake mint, TAC counterfeit jetton) the *entire* exploit is an identity collision and no number is
  wrong.
- **Q2 Amount & backing** — is the number right *and is what's issued backed*? The four number-failures
  (stale/forged/miscomputed/unbounded) plus **conservation** (`issued ≤ backing`) as a first-class
  invariant reconciled against live balances. Lens C also gained the **signed/negative-input** pattern
  (Aftermath, Dango, Drips, Chi, Denaria — a deposit path that reverses into a withdrawal).
- **Q3 Does the check itself hold?** — the new **Lens G**. The guard passes, nothing is forged, but it
  enforces the wrong predicate or a mismatched scope, or counts a proxy for the invariant, or its result
  is discarded, or the validation mutates state. This is the hardest lens (nothing looks malformed) and
  the single most common 2026 shape.

Plus a **fleet cross-cutting pass** (version skew / shared dependency / fork-drift-that-removes-a-check),
a **guard-pricing note** that when the guard is a risk *parameter* the fix is a parameter not code
(Yieldblox, Term, Moonwell), and an explicit **scope-of-methodology** statement: this finds on-chain
logic bugs and by construction cannot find the key/opsec/infra compromises that were the four largest
losses of the period — a clean verdict must say so.

Module sharpening from the substrate sweep: Cosmos-EVM mirrored-balance underflow + caller→account auth
mapping (KiiChain/BounceBit); the TSS/consensus/bridge-vault layer as in-scope for app-chains (THORChain,
Harmony); Solana account-aliasing (`require_keys_neq`) and durable nonces; Move VM-level type-safety and
reward-index inflation; EVM ERC-1271-unchecked-success; Bridge amount-equivalence ("the check in neither
chain") and parser/receipt-binding.

## What was deliberately NOT added

Discipline mattered as much as coverage. Rejected despite appearing in the corpus:
- **An intent/solver/batch-auction lens** — no in-scope 2026 headline; the one RFQ case (TrustedVolumes)
  is plain AUTH-MISSING. Would be padding.
- **A reorg/finality/sequencer lens** — discussed as risk, no marquee in-scope incident; existing slots
  would hold it if it occurred.
- **Cairo/TON/NEAR modules** — one incident each; the core three-questions + bridge module already carry
  their shapes. A module per chain would be length without yield.
- **A separate "economic-design" axis** — guard-pricing already handles "the guard is a number, read the
  number"; only a one-line note (fix-is-a-parameter) was warranted.

The honest headline: across 146 incidents the framework needed **one new axis (Q3), one redefinition
(issuance as exit), one elevation (conservation), and one new pass (fleet)** — not a rewrite. That the
corpus mostly *confirmed* the structure is the result, not a failure of it; the additions are the places
it genuinely didn't.

v2 is preserved as `CORE.v2.md`, v1 as `CORE.v1.md`, for diffing.

---

# v4 — acting on external review

A round of external critique (three reviewers) landed on v3. Most of it was sharp; some predated the
146-incident corpus and assumed "hacks are mainly direct contract code." Judged against what we actually
found, and against the standing principle that the prompt must **not lead the auditor toward specific
known bugs** (every incident is different; naming last year's steers toward it and away from the novel
one). Verdicts:

## Adopted

- **Cut §0's base-rate prior.** The strongest critique. "Most systems have a live path / expect to find
  something" is (a) uncitable — our corpus is survivorship (already-exploited protocols), so it says
  nothing about an arbitrary target's base rate; (b) miscalibrated for a blue-chip's fifth audit; and
  (c) the exact suggestibility lever the rest of the document disclaims. Replaced with a symmetric
  mandate: effort is mandatory, the conclusion is free, *carry no prior either way*. The three
  mechanisms (denominators, kill quota, Null Report) already supply the anti-skim floor without a
  probability claim.
- **Strip uncitable frequency superlatives** ("the two largest pure-code losses…", "the single most
  common shape of the last year", "the single most common low-cap drain"). These both break the
  document's own evidence rule and steer toward known bugs — the precise failure the user has flagged
  since the first message. Kept the *general checks*; removed the *statistics* that told the auditor
  what to expect.
- **Governance pricing, two fixes.** (1) Price capture by the *cheaper* of open-market float **and the
  protocol's own deposit-to-votes/mint/wrap path** — the latter is how thin-governance captures actually
  happen (Term, Token of Power minting 10B in one tx). (2) Cheap votes are a finding *only when the
  timelock can't save users* — connected the float check to the timelock/exit-window check, which kills
  the false positive of flagging every low-float token.
- **Warp rule, split by kind.** Mechanical time (vesting, epochs, a message that only needs to sit) has
  no defender → warp freely. A reaction-window delay (governance/pause timelock whose purpose is human
  veto) is a real guard → don't silently delete the defender's turn; price whether the reaction is real,
  and if the path only works because the veto never fires, report it *contingent on that*. Plus the
  honesty caveat that the fork freezes market prices while advancing only the clock.
- **Value-destruction scoped to a beneficiary.** "Counts even where attacker gain is small" now requires
  *someone comes out ahead at users' expense*; pure no-beneficiary destruction (bricking, freezing, a
  chain halt) is explicitly griefing/DoS → the team's lane, in scope only as a lever inside a theft
  chain. Resolves the contradiction with the out-of-scope list and gives liveness an explicit home.
- **Presumptive finding.** §4's "a mispriced guard is a finding before you have a path" now reads
  *presumptive* finding, carried to §6/§8 to be confirmed by the path/PoC or labeled `UNPROVEN` —
  reconciling it with the execution-gates-reporting rule.
- **Kill quota scaled, not flat.** Reframed from "three per lens per seam" (ritual on trivial seams,
  gameable) to *proportional to what the seam controls, with a floor that no material value-mover gets
  zero*. Keeps the anti-skim force where it matters, drops the busywork.
- **Substrate leaks.** "The chain's own verification attests" generalized to reproducible-build/program-
  hash binding for Cosmos/Solana/Move, not just EVM explorers. §A gained intake for the other named
  inputs (bare address, chain+height+binary, two bridge endpoints), each pinning its own state.
- **Trimmed the seven questions** to the three techniques the lenses don't otherwise force (compare
  siblings, read constants as secrets, count approvals as value) — the other four were pure lens
  restatements, so this removes a whole overlapping taxonomy and the reconciliation load with it.

## Considered and declined (with reason)

- **"The exit-first / number-first spine is an overstated universal law."** Already resolved in v3: the
  spine is three co-equal questions, and Q1 (authorization & identity) is *first*, not subordinate — a
  missing `onlyOwner` is a wrong *caller*, which Q1 owns outright. The v4 §0 rewrite removes the last
  number-first lean. No structural change needed; the critique was reading v2's "wrong number" spine.
- **"Make control-capture a co-equal hunt."** It already is (Q1). Adopted only the sharper governance
  *pricing* underneath it.
- **Softening the fleet "highest-probability finding" claim** — kept as "among the highest," because it
  is a *logical* claim (a public unpatched advisory is by definition highly likely present), not an
  uncited corpus statistic, and it drives a concrete, cheap, high-yield check.

Net: v4 is almost entirely subtraction and calibration — no new lens, no new axis. It removes the two
places the document held itself to a lower evidentiary bar than it holds the auditor (the base-rate
prior, the frequency superlatives), and sands the two spots that move real findings toward or away from
the report (governance pricing, warp). v3 is preserved as `CORE.v3.md`.

## v4, extended to the modules

The v4 review was aimed at the CORE, but two of its fixes are systemic and the modules carried the same
issues — so leaving them CORE-only would have been inconsistent:

- **Leading language / incident-steering.** The modules were where the most specific "biggest hack of
  the year, go find it" framing lived (a Move opener citing "the single largest in-scope loss of the
  last year, ~$223M"; "the Cetus bug lived in…"; "a real 2026 drain paid out ~$11.6M"; "Wormhole's
  $325M"; `Term-shaped`/`Arrakis-shaped`/`Allbridge-shaped` shorthands). All of it now teaches the
  *mechanism/shape* with the incident name, dollar figure, and ranking removed — the mechanism is what
  instructs; the name only adds the steer this whole project exists to avoid. A full sweep confirms no
  incident name, dollar figure, or frequency superlative remains in CORE or any module. The two
  surviving "most common" phrases are an auditing-practice warning (asserting set contents without
  enumeration) and the descriptor "theft-shaped" — neither steers toward a bug.
- **Substrate verification.** "The chain's own verification attests" is EVM-specific; the Cosmos, Solana
  (`solana-verify`), and Move (published-bytecode compare) modules now state the reproducible-build /
  program-hash binding as their own source-of-truth mechanism.

And one alignment carry-through: the EVM module's governance guard-pricing now mirrors CORE §4 — price
capture by the cheaper of open-market float and the **deposit-to-votes** path, and gate the finding on
whether the timelock can actually save users. The substrate *mechanics* (proxy resolution, the Solana
four/five-check table, Move shift-truncation, the precompile mirror-desync) were left intact — those are
necessary knowledge, not leading.

## v4.1 — composed-of / backed-by dependency (a scoping gap in the mapping)

A live case surfaced the sharpest remaining gap, and it was a *scoping* gap, not a detection one: an
auditor points at protocol A, audits it, finds nothing — correctly, A's code is sound — while the money
leaves through protocol B, whose token/LP-share/receipt A *holds* as backing or backstop. A's call-graph
never touches B's buggy function; A merely holds the asset B issues. The prompt already handled the
*read/price* flavor of composition ("an AMM reserve you price against, a vault share ratio you deposit
into, a lending index you read"), but not the *hold* flavor.

Research confirms this is a general, named class (DeFi composability / systemic dependency), with several
flavors sharing one root — the target's value is impaired by a defect in a system it doesn't control but
structurally depends on: **pricing** (read an external price — already covered), **backing/holding** (hold
a claim on an external protocol — the gap), **strategy** (deposit into an external yield source), and
**shared collateral/liquidity**. Only backing/holding was under-covered.

Four small, mutually-reinforcing touches, all general (no case cited):
- **Lens F** gains a "composed-of / backed-by dependency" bullet: enumerate what each issued unit is
  backed by and what the system holds as reserve/collateral/backstop/strategy; any holding that is a claim
  on an external protocol puts that protocol's value-integrity in scope; follow into it as you would the
  target; you find these by asking "what is each holding a claim on," not by following calls.
- **Inventory register** now forces the resolution: for every held reserve/collateral/backing asset,
  resolve its issuer and add it as an in-scope-for-value-integrity row — never "inert," never a bare
  external name.
- **§8** extends "a surface you named can't be deferred" to explicitly include an external protocol whose
  held token/share would devalue what the target's users are owed.
- **§9** adds the matching artifact-time check.

Scope discipline held: this is the one flavor that was genuinely thin; the pricing/read flavor was left
alone (already covered), and no incident is named in the shipped prompt (the `cometbft` string in the
Cosmos module is the unrelated consensus engine).

## v4.2 — DISCOVERY.md: reorienting triage to urgency

The discovery/triage front-end (separate from the deep-audit CORE.md) was reranking the live universe by
abstract hack-*likelihood*. That is the wrong axis for a small defender trying to prevent the *next* loss:
it treats a bug nobody has found yet the same as one whose exploit is already written and circulating.
DISCOVERY.md reranks by **time-to-exploitation** — urgency is highest where the technique is already
public AND the fix is absent from the deployed artifact AND live value is reachable. Consequences:
remediation status is promoted from a footnote to the primary ranking driver, and "the deployed artifact,
not the repo, decides" becomes the fastest confirm/kill in the whole flow.

Five urgency tiers, worked top-down: (1) unremediated-known (public technique, fix not in the deployed
bytecode), (2) shared-dependency cluster (a published advisory live across a fork/vendored/sovereign
population with no patch-compliance mechanism — vendored forks are the highest-yield sub-case because
dependency scans miss them), (3) composed-of dependency (the target holds an external protocol's asset
whose issuer is exposed — the CORE.md v4.1 addition, applied to triage), (4) fork-of-recent-victim,
(5) novel-high-fit (the old likelihood-first mode, correctly demoted below the hot clocks). Supply-
conservation is called out as the one root-cause-agnostic detector that flags a family member before its
indicator is written. Kept general — no incident named as a target; it re-derives families from whatever
the current corpus is. It preserves the discipline the discovery work had earned (evidence levels, read-
only, no "vulnerable" language, ledger/no-repetition, the small-entity band, value-at-risk beside the
score) and hands off to CORE.md.

## v4.3 — DISCOVERY.md: don't point at drained victims

A sharp question surfaced a real hole in DISCOVERY.md: urgency-first ranking risks pointing at the
*victim* of a fresh incident, which is usually already drained. Fix, three small edits, philosophy
unchanged (incident-derived-urgency-above-novel is correct for "prevent the next loss fastest"):
- **§0** now states the reframe: the incident is *evidence* (the technique is public and the code
  unpatched); the *target* is the un-hit deployment on the same code — the fork, sibling, vendored copy,
  dependent. Read the drained victim to learn the technique; rank its un-hit relatives to prevent the
  loss. "A hot clock over an empty vault is not a candidate."
- **§2** promotes live reachable value from a score component to a **hard gate**, pinned to current
  holdings read at the pinned point (never historical TVL) — so a drained victim is excluded regardless
  of how fresh its incident is. Exception: the **restore window** (restarted/refunded/whitehat-restored
  on still-unpatched code is holding real money again on the same open door).
- **§5** gates before it scores, and the value axis was corrected to reward *reachability*, not
  *magnitude* — putting dollar size back into the score would have re-introduced the exposure-weighting
  the operator explicitly rejected. Magnitude stays the gate (empty→out, band) and the tiebreaker
  (prefer fuller among equals), never the score.

## v4.4 — making the eval actually runnable, and blind

"How do I test the eval, still blindly?" exposed a genuine gap: the harness blinded the *brief* and
graded the *transcript*, but had no glue to assemble the exact auditor bundle, no automatic leak-check,
and no written procedure. Added:
- **`run_case.sh`** now assembles `PROMPT_BUNDLE.md` (CORE.md + the case's module(s) + the blinded brief
  — the only thing the auditor may see) and **leak-checks** it: hard-fails if any incident name (from the
  grader's retrieval list) or grader-only field is present, warns on coincidental capitalised words.
- **`RUNBOOK.md`** — the end-to-end blind procedure: the two-actor separation (auditor blind / grader
  sees answer), building the one-block-before fork, running a fresh auditor context, grading
  PATH/DERIVED/PROVEN, running controls for FP, keeping the suite honest (retire leaked cases, weight
  obscure/recent), and authoring new cases.
- The leak-check immediately caught a real bug in the grader: the retrieval list contained framework/
  chain names (`aragon`, `zodiac`, `cctp`, `cosmos evm`, `balancer`, `sui`) that legitimately appear in
  the modules — so they were both false de-blinders and useless recall signals (an auditor echoing the
  module's vocabulary isn't recalling the incident). Pruned to 26 genuine incident names, all verified
  absent from CORE and every module, and re-checked: every case's bundle now passes the leak check.

---

# v5 — the first evidence from real runs: the auditor became a scanner

Fourteen real CORE.md runs came back, every one "No verified finding." This is the first round driven by
**observed behaviour** rather than by a corpus of other people's incidents, and it changed the diagnosis
from "what shape is missing" to "what does the document actually make an auditor do."

## What the runs showed

All fourteen collapsed to the same four steps: receive a known-advisory hypothesis, pin the binary, check
whether the affected surface is live and the version in range, answer no, report clean. That is
dependency scanning. It cannot produce a novel finding because it never looks for one. Thirteen of the
fourteen were the same advisory family; nine died at the first check on surface-absence.

The decisive observation is **not** that instructions were missing. §A already said to treat a handed
hypothesis as "a hypothesis to test first and then set aside, never the audit." Register 8 already said an
anomaly "must not be filtered as one — chase it before you judge it." §9 already asked whether the exits
were "enumerated as a closed set." **Fourteen runs read all three and did the opposite.** So a fifth
restatement would lose too, and the filter for this round became: only three kinds of edit can change
behaviour — (a) delete text that competes with the correct instruction, (b) create a count nobody can
currently produce, (c) move a private self-check into the published artifact, where skipping it is
legible to a reader. Every change below is one of those three; everything that was only a restatement was
cut, however true it read.

Second structural finding: CORE's method surface was almost entirely **recognitive** — match the system
against remembered shapes — with only two generative moves in the whole document (Lens F's degenerate
values, Lens C's splitting). Novel bugs come from generative moves, and the one genuinely uncounted
generative move was trapped in `modules/SOLANA.md`, invisible to any non-Solana audit, in direct
violation of the document's own split ("the modules carry mechanics; this carries the method").

## Adopted

- **Lens E gains its mirror — distinctness.** The lens covered identifiers forced to mean one thing; it
  had nothing on one thing handed to two parameters written to assume they differ. Per pair, cite the
  line enforcing distinctness or record its absence, with the pair count added to the lens denominator.
  Generative from a signature alone — no advisory, no remembered shape. Shipped with the §5 lens→question
  map repair (E added to Q2 and Q3): without it the mirror sits in a lens the map files under Q1 only,
  reachable only through a gate the affected exits pass cleanly.
- **Lens F drops the duplicated advisory instruction.** The bullet ranks surfaces by how little they have
  been read, then filed the most-read artifact about any dependency in the least-read list. The identical
  instruction survives in the fleet pass and the §9 checklist, so nothing was lost. This completes the v4
  superlative purge, which had missed the instance attached to an actionable list — the worst kind,
  because it converts directly into a workplan. `modules/COSMOS_APPCHAIN.md` carried the same superlative
  and was cut too; v4's claim that none remained in any module was simply wrong.
- **The verdict carries its denominators** — exits enumerated vs. exits with all three questions answered.
  Mismatch prints **incomplete** and names what was not reached. The verdict was the only artifact in the
  report whose required content the document never specified (nine words), which is how a run could file
  "chain exits were not fully enumerated" in open questions under a "no verified finding" headline and
  break nothing.
- **§9 gains an anomaly-register check**: a dismissal of the form "harmless unless X" names X as the test
  you still owe. Register 8 was the only value-bearing register with no line in the enforcement list, and
  a run realised exactly that gap — a live anomaly of the target shape disposed of in one line.
- **The fleet pass reads the diff both ways.** It was direction-locked on absence: a deleted guard, an
  unapplied fix, a sibling *missing* the guard. Nothing pointed at what a fork or a patch **added**, so a
  version above an advisory's affected range read as a clean kill — which is what happened on the one
  target whose vulnerable surface was actually live, where novel hotfix methods went unaudited. The
  load-bearing half is the new count (entry points added or changed versus upstream, each dispositioned);
  the Count line had stopped at a fix-presence boolean.
- **§A: land one unprivileged call against a fork before code reading begins.** The simulation of the
  revised document rated it *probably* rather than *yes* on a no-advisory behavioural bug, and named the
  reason: the chain surfaces a recorded absence but nothing converts it into an executed test. Four runs
  discovered they had no harness at write-up time. Learning it on day one bounds the engagement instead.
- **Manifest provenance.** Evidence files are tagged `deployment` or `reference`, and the check counts
  claims about deployed behaviour resting on `reference` alone; that count must be zero. A path-exists
  check passes a repo checkout, so the one mechanical guard in the document was blind to the §3 violation
  that costs the most — concluding what the deployment does, or does not do, from what is not the
  deployment. One run concluded surface-absence from an unbound repo tree while recording in the same
  report that the binary was not source-bound; that is the single place in the corpus where a clean
  verdict could be sitting over an open door.

## Rejected (and why — these were argued and lost)

- **A path-equivalence / differential lens.** Covered four times over (Lens C's splitting carries the
  N-vs-1 differential with a count; "compare siblings" carries the rest), and the calibration target
  refutes it directly: a same-asset route is a *degenerate input*, not two routes to one outcome. The
  distinctness mirror reaches it directly; a differential lens would reach it only by accident.
- **Restating §3 for absence claims** ("a claim of absence must cite a deployment-bound artifact"). The
  runs that made this error **already published the binding failure in the same report as the conclusion
  it invalidates** — the disclosure was there and changed no verdict, because binding status and the
  absence conclusion lived in different sections and nobody reconciled them. A rule requiring a
  disclosure already being made is a restatement with a citation field. What survived instead is the
  manifest count above, which is a mechanism rather than a principle. Also a category error in the
  original proposal: "this version is past the fix" is a *presence* claim inferred from a version string,
  which no absence rule can reach — the fleet-pass change is what reaches it.
- **Moving §6 / a day-one harness mandate as a restructure.** Reads section order as execution order;
  §0 already says to read the whole document first and §A is the literal first action. Only the §A
  one-call residue survived.
- **Strengthening §A's "hypothesis to test first and then set aside".** The text is already exactly right
  and it lost fourteen times. Deleting the competing advisory emphasis is what helps; adding volume to
  correct text is not.
- **Capping candidates per family, an Algorand/AVM module, a tenth register, any base-rate prior.** The
  first is a DISCOVERY concern and was de-scoped; the second re-litigates v3's per-chain-module rejection
  and is contradicted by the AVM run, which produced a complete substrate-free kill and thereby
  *vindicated* the substrate-free method; the third folds into Lens E; the fourth is the v4 cut.
- **"A patch is rushed and less reviewed."** Cut from the fleet-pass change as a base-rate prior about
  where bugs live. What remains is definitional — code that did not exist upstream was not covered by
  upstream's review — the same logical footing v4 kept for the unapplied-advisory claim.

## Eval

`case-10-assumed-distinctness` was added because the suite had nine cases and **none** encoded the shape
this round is aimed at — the change would have shipped unmeasurable. It is deliberately built on
`EVM.md`, which carries nothing about distinctness, rather than `SOLANA.md`, which has an explicit
aliasing section that would hand the auditor the answer; the case therefore tests whether CORE's own
method carries the move. Its `must_not` list encodes the real false-positive traps: the external funding
protocol is correct code and is not the finding, and the pool's own constant-product check is correct for
every input where the two references differ. `grade.py` gains the matching signature and the incident
names (all verified absent from CORE and every module); `run_case.sh`'s soft-warn stop-list was widened
so the leak channel warns on genuine names rather than on ordinary English.

## Honest status

Every claim in this section is about the *document*. The 14 runs measured the old prompt; **nothing here
has been measured against the new one.** The catch-rate reasoning is a traced simulation, not a result,
and it rated itself *probably*. `case-10` exists so that this can be settled empirically rather than
argued.

---

# v6 — the finding/open-question boundary (operator-directed, from three real runs)

The first real runs on recent incidents exposed a systematic behaviour the operator named directly:
CORE keeps **establishing a structural defect and then filing it as an open question or a killed
candidate instead of a finding.** Three runs, same shape:
- **case-12 run 1** (Term Finance governance): surfaced the fund-controlling governance surface as
  open-question #1 with the full-TVL cost, returned "incomplete" — but did not report it as a finding
  ("I did not substantiate a beneficiary path … so it is not reported as a finding").
- **case-12 run 2** (with a harness effort-nudge): still no finding — killed the stale-NAV candidate
  (correctly: `maxRedeem` bounds it) and gated governance out as "3-of-8 Safe, no outsider-acquirable
  path," never checking that vault shares are the votes.
- **case-13** (MayaChain): found and PoC-proved the ObservedTxVoter overwrite, then filed the net-positive
  completion as UNPROVEN/OPEN rather than a finding.

The effort-nudge (added to the harness START_HERE between run 1 and run 2) was the diagnostic: run 2 had
it and still parked the defect. So the blocker is **not effort** — it is **classification**. The operator's
diagnosis was better than the "needs a bigger budget" hypothesis: the gate is letting an established,
unclosed structural defect fall through a "no beneficiary path → silently not a finding" hole.

CORE already contained the rule (§8: "an unproven link does not lower severity unless you cite the code
that closes it; 'I could not find a way' is a statement about your search, not a guard … must not be
demoted to an open question"; §4's "presumptive finding"). The machinery existed and the auditor overrode
it. So v6 does not add doctrine — it makes the existing rule **bind** and closes the escape hatch.

## Adopted

- **§8 — an established structural defect is a finding the moment its preconditions hold, PoC or not.**
  A guard priced below what it protects and shown acquirable on live state; a value an exit trusts shown
  stale/manipulable; an issuance with no backing bound — each is a finding at the severity of the funds it
  exposes, carried `UNPROVEN` with the unbuilt link named, **not** an open question and **not** a killed
  candidate. Every "I did not substantiate a beneficiary path" must resolve into exactly one of two, never
  a silent third: *a cited line closes the path → killed* (§7), or *you could not build the PoC → UNPROVEN
  finding at this severity*. Explicitly does **not** loosen the gate: a precondition you could not
  establish stays an open question; a path a cited guard truly closes stays killed — so the correct
  stale-NAV kill in run 2 (bounded by `maxRedeem`) still reads as killed, no new false positive.
- **§7 — "I could not build the beneficiary path" is not a rebuttal.** Only a cited closing line is; an
  unclosed path you could not weaponize is UNPROVEN, not killed. Stops the kill step from absorbing
  established defects.
- **§4 — a fixed-looking admin does not end the acquire-price question.** Where control looks like a
  multisig or an owner, check whether the protocol's own share/LP/deposit token confers votes or veto over
  that admin's fund-moving actions — in a vault the shares you mint by depositing are frequently the
  governance weight over the role that moves the deposited funds. This is the specific step run 2 skipped
  when it concluded "control is a 3-of-8 Safe, not acquirable." Generalizes §4's existing deposit-to-votes.

## Rejected / removed

- **The COMPLETENESS effort-nudge is removed from the harness START_HERE.** It was a diagnostic to isolate
  effort vs classification; run 2 carried it and still parked the defect, so it is not the fix, and leaving
  a harness nudge in place would confound future eval reads (the auditor's completeness behaviour should
  come from CORE, not the rig).

## Honesty / limitation

The case-12 target (`0x184f2e57…`) turned out to be an intermediate that holds no WETH balance at the
pinned block — the value in this Yearn-v3-style system lives as strategy positions, reachable only through
governance — so case-12's specific "no finding" is partly a mis-pinned case, not purely a CORE result. The
v6 change rests on the **behaviour pattern across all three runs plus the operator's directive**, not on
case-12's exact pin, and it was checked to introduce no false positive against run 2's correct kill. The
FP risk (promoting a defect that a guard actually closes) is explicitly excluded by the killed-XOR-unproven
resolution. Whether it converts a real run's open-question into a finding is the next thing to measure.

## v6.1 — de-normalize open questions, force the fork, proof-state in findings.md

Built from the v6 base, not stacked on it. An earlier draft this session added the same intent as two
long blocks (a rewritten register 9, then a ~12-line §8 addition naming a governance-capture PoC recipe);
that was the "longer = better, only ever add" trap and it hard-coded one technique. Reset to v6 and
reapplied as removal/rewrite. Net effect: +6 lines over v6, general, no named techniques.

### Evidence — two clean v6 re-runs on corrected setups

Maya (case-13d, pre-fix commit `ff018576a6ea`, pinned height) and Term (case-12, the real ETH Meta Vault
`0x26fcb50e` over a relay-routed pinned fork). Both did the hard part right; both `findings.md` still said
"No verified findings." Graded against the transcript (the grader reads `transcript.txt`, not
`findings.md`):

- **Maya `PATH 5/5, PROVEN yes`.** Reconstructed the whole chain — message-level atomic unit, the
  cross-message `txid` overwrite, the false-positive detector, the uncapped subsidy, the pool conversion —
  and proved the overwrite with a keeper-level PoC, plus live-chain balance-delta proof. Its one open
  question was the honest external blocker (private `tss-lib` won't build). The `UNPROVEN` finding was
  real and well-formed — and *excluded from `findings.md`* because the auditor read "verified" as
  "money-out replay built." (`DERIVED: NO` is the known app-chain blinding weakness, not a method miss.)
- **Term `PATH 4/5, PROVEN no, MISS`.** Resolved the EIP-1167 proxy, read `totalAssets=2926 WETH`, and
  proved cheap capture (~0.55 WETH buys majority over the role governing the vault). It missed only
  must_reach[4] — build the acquire/queue/warp PoC on the fork — because it filed that exact step as an
  open question with a fork-executable settling action, after trying two direct owner-only calls (which
  correctly revert).

Diagnosis: the method works — it found both bugs. Two hatches let the *report* throw the result away.
(1) Open questions were **normalized**: register 9 sat as report-item #1 above the verdict, and its own
definition invited punts ("a path you couldn't construct" — which §8 already calls an `UNPROVEN`
finding). (2) `findings.md` said "the verified findings," one word that filters out every `UNPROVEN`
finding, so the deliverable reads "none" while a serious defect stands.

### Adopted (from v6, by removal/rewrite)

- **Register 9 de-normalized.** Scoped to *only* what the auditor cannot resolve with the access it has
  here (a dependency that won't build, a source that won't bind, a height the node won't serve). If the
  settling action is something it could do here — decompile, reconstruct, stand up the fork and run it —
  it is unfinished work, done before reporting, not a question. General; no technique named. This also
  carries the "force the fork" ask: a fork-runnable settling action is the PoC owed, not a question.
- **Removed open questions' pride of place.** They no longer lead the report above the verdict; findings
  (proven and `UNPROVEN` alike) take that anti-burial slot, and the genuine external blockers fold into
  "the rest" as verdict caveats. The anti-burial job now protects *findings*, which is what it was for.
- **`findings.md` carries every finding**, proven and `UNPROVEN`, tagged with proof-state; "verified" is
  not a gate it applies, and it may not say "no findings" while a live defect stands unproven. One-line
  change to the deliverable instruction — the "go easy on verified" ask.

### Deliberately NOT done

- **Did not delete the open-questions register.** The operator floated "shouldn't exist at all" but the
  disease was normalization, not existence: genuine external blockers (Maya's private dependency) deserve
  one visible, honest slot that tells the operator what to provide to finish. Deleting it scatters that
  disclosure into finding text and makes it less visible. De-normalizing achieves the goal; deleting
  overshoots and touches the anomaly→question path and the Null Report needlessly.
- **Dropped the governance-capture PoC recipe** the interim draft added to §8. It was a single named
  technique; the general rules (fork-runnable ⇒ do it; unbuilt live-defect path ⇒ `UNPROVEN`, not a
  question; §6 execution-first) cover the same failure without teaching one case.
- **No new mandate that every finding needs a fork PoC.** That would wrongly punish genuinely blocked
  cases (Maya). `UNPROVEN` with the external blocker named stays honest and first-class.
- **No verdict-wording change, no new prior.** Term's verdict already read "incomplete" honestly; once
  the capture is a finding, the verdict carries it. Nothing added steers toward "expect a bug."

### Rig fixes this round (harness, not CORE — kept)

These made the two re-runs valid and are independent of the CORE change:
- **case-12 target corrected** to the funded ETH Meta Vault `0x26fcb50e` (the case's `0x184f2e57` is the
  empty "Fixed Recipient WETH Exit Strategy" — zero balance at the pin; auditing it guarantees "no
  finding"). Traced on-chain from the drain.
- **START_HERE pinned-fork-only** (EVM) and **pinned-height + pre-fix-version** (Cosmos): a
  halted-then-patched chain's live head / current version is post-fix; reading it is a false-clean (the
  original Term case-12c bug). Advancing the *local* fork for a PoC stays allowed.
- **anvil-through-proxy relay** (`rpc_forward.py`): in a proxied sandbox anvil's fork transport ignores
  `HTTPS_PROXY` and egress is blocked (403 from istio-envoy); a loopback curl relay does the egress.
  `stage_real.sh` auto-detects the proxy and routes through it.

### Next to measure

Term on this build: does it stop filing the capture as a question and either build the fork PoC
(must_reach[4], `PROVEN`) or surface it as an `UNPROVEN` finding in `findings.md` at TVL severity? Maya
should stay 5/5 with its finding now inside `findings.md`.

## §4 — an acquire-price the fork can pay is never `UNVERIFIED`

Measured that build. Four re-runs (Maya 13e/13f, Term 12e/12f), 'e' before the de-normalization, 'f'
after. What moved, from the transcripts (grader signatures are coarse here — read the content):
- **Maya:** the `UNPROVEN` finding now lands in `findings.md` (the verified-gate bug is gone), and 13f
  anchors severity to the funds the defect exposes ($3.14M) vs 13e's concrete slice ($31k). Honest
  `UNPROVEN` (harness blocked by a private dependency). No new gap.
- **Term:** 12e punted through open questions (`OQ-1/OQ-2`); 12f has **"Open Questions: None"** and
  actually worked the governance plane — the de-normalization bound. But 12f still didn't land the
  finding: it priced only the *open-market* route ("can't buy the existing float", blockers = liquidity /
  borrowability) and stamped the *through-the-protocol* deposit route `UNVERIFIED` / "not priceable from
  state alone", then carried it as "uncovered exposure / INCOMPLETE". The open-questions door was shut, so
  the same punt walked through a sibling door.

The deposit route is **fork-executable** — deposit, read whether voting/veto weight over the fund-moving
role crossed threshold, then queue + warp (contingent on the veto per §6). 12e had even run an outsider
deposit→redeem round-trip on the same fork, but aimed it only at economic profit, never at "did my weight
rise?". §4(b) already commands pricing the deposit-to-votes route ("a voting token you never priced is a
guard you never audited"), but nothing said that price is an action you *perform on the fork*, so it may
never be returned `UNVERIFIED` — a label that fits only a route needing off-fork data (an existing float's
real market liquidity).

### Adopted
- **§4, one sentence** appended to the acquire-pricing paragraph, as the complement of the existing
  "where the price depends on a live number" sentence: where the price is instead an action the fork can
  perform (deposit / mint / stake / bond → role or weight), perform it and read whether the privilege
  followed; a cost the fork itself can pay is never `UNVERIFIED`. General across substrates (validator
  bonding, whitelist mint, role stake), conclusion-free (the read returns an honest negative when the
  privilege doesn't follow), no incident or technique named.

### Verification (diagnose → refute workflow, 7 agents)
- The Term fix survived both adversarial refuters (0/2) — real gap, general, not already covered by a
  single line, within the one-sentence ideal.
- **Maya: no change** — an independent lens argued it and 0 refuters dissented; the "didn't carry to the
  beneficiary" residual is already covered by §1 (issuance is an exit), §4 (subsidy vs a near-empty
  reserve), §7 (argue the other side), §8. Run-variance in which monetization the auditor chased, not a
  method gap.
- **Rejected: a broad "label-agnostic" §8 rewrite** (make the fork-doable rule name `UNVERIFIED` /
  uncovered / dormant / incomplete together) — refuted 2/2 as padding: "dormant" is already closed
  verbatim at §8, and §8's two-fate resolution already makes the third door illegitimate; the one place
  that actually needed the operative rule was §4's acquire-price, which the targeted sentence fixes.

## §A + register 9 — the environment is the auditor's, with full rights

Evidence: two fresh general runs (Cronos, Canto) both killed the handed advisory and then accepted
**self-fixable** environment failures as hard walls: "Go >=1.25.0 not satisfied → binary not replayed"
(Cronos), and "modules 403 from proxy.golang.org → no reproducible build," "public RPC stale → couldn't
confirm" (Canto). None of those are blockers — the auditor runs with full rights over its environment and
can update Go, set GOPROXY / a mirror, stand up its own node, or pick another endpoint. It just didn't.

The register-9 wording licensed it: "a dependency that won't build" was listed as a *legitimate* open
question, so "won't build because the toolchain is old" read as a blocker. Operator's point, exact: an
open question is only for something *neither* the operator nor the auditor can lift; anything the operator
could fix by reconfiguring (newer Go, a working endpoint), the auditor can fix itself.

### Adopted
- **§A setup:** "treat this environment as yours, with full rights" — install what's absent, update a
  toolchain too old, set the module proxy/mirror a fetch refuses, stand up your own node or pick another
  endpoint. A tooling/build/fetch failure you can clear is a chore, not a limitation. The fork-can't-be-
  built caveat is now conditioned on *after exercising those rights* and reserved for a genuine external
  blocker (private dependency nobody has, a service that refuses the given credential).
- **Register 9:** reserved for a genuine external blocker you cannot lift with those rights; a toolchain
  too old, a missing package, a 403 fetch, a stale/failing public endpoint are explicitly "yours to fix,"
  never open questions. General (any substrate, any tool), no prior added — it removes a false-blocker
  license the two runs exposed.
