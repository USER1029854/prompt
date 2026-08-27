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
