# Adversarial DeFi audit prompt — v2

A rewrite of the audit prompt, built by studying why real seven-figure exploits walked past rigorous
reviews. Input is still a DefiLlama link (or an address / height / bridge pair). Output is still how
an unprivileged attacker takes value they aren't entitled to, proven on a fork — or an honest clean
verdict with a Null Report.

## What's here

```
CORE.md                     the audit method. Read first. Spine: exits -> the numbers they trust -> the
                            four ways a number is wrong (stale / forged / miscomputed / unbounded).
CORE.v1/v2/v3.md            previous versions, kept for diffing (v1 seam-first, v2 wrong-number
                            spine, v3 three-question spine; v4 = external-review calibration).
modules/
  EVM.md                    proxies, factories, guard pricing, storage, callbacks, unchecked/rounding,
                            deferred settlement, proof verifiers
  COSMOS_APPCHAIN.md        SDK keepers/handlers, the message atomic unit, the EVM-precompile seam, Dec rounding
  SOLANA.md                 the four account-validation checks that are ~every Solana bug, proof/sysvar seams
  MOVE_SUI.md               abort-on-overflow vs silent shift/cast truncation, the capability/object model,
                            VM-level type safety
  BRIDGE.md                 the three questions of every bridge; "audit the side you can't read"
eval/                       test whether the prompt could have caught history — scoring the PATH, not the answer
  README.md                 the contamination problem and the three rules that beat it
  cases/                    blinded historical incidents with must_reach observations
  controls/                 clean targets — measures false positives (the number everyone forgets)
  grade.py                  mechanical PATH / DERIVED / PROVEN / FP grader (self-tested)
  run_case.sh              sets up a blinded run without leaking the answer
ANALYSIS.md                 WHY the rewrite is shaped this way — reviewer-only, keep it off the auditor
```

## How to run an audit

1. Give the auditor **CORE.md** + the **module(s)** for the substrate. A bridge loads BRIDGE.md and
   both sides' modules; a Cosmos-EVM chain loads COSMOS_APPCHAIN.md and EVM.md.
2. Hand it the target (link / address / height+binary / bridge pair) and a fork endpoint. Nothing
   else — no hints.
3. It works the nine registers in `CORE.md §2` on disk, runs the five passes and six lenses, prices
   every guard, executes against a fork, argues the other side, and writes `findings.md`.

## The ideas that changed vs. the old prompt

0. **One spine — three questions per exit.** The system parts with value, or *issues a claim on value*,
   through an exit. Ask: is the right party acting on the real thing (**authorization & identity**); is
   the number right and is what's issued backed (**amount & backing**); and does the guard actually
   enforce the invariant or just pass while checking the wrong thing (**Q3 — the check that doesn't
   hold**). Q3 was the single most common 2026 shape; issuance-as-exit and the `issued ≤ backing`
   conservation invariant capture the dominant bridge/mint theft. Built from ~110 incidents, Feb–Aug
   2026. (`CORE.md §1`, reasoning in `ANALYSIS.md` v3)
1. **Core math is first-class.** The two biggest pure-code losses of the year were a wrong shift-threshold
   and a floor-division. "The language aborts on overflow" is not proof the math is safe — shifts and
   casts truncate silently. Lens C hunts rounding direction, truncation at edges, splitting, and deferred
   settlement, and §6 fuzzes/proves the math instead of eyeballing it. (`CORE.md §5 C`)
2. **Price every guard.** "Guarded" is not "safe." Governance that costs $2k to seize, a timelock
   that reconfigures itself, a TWAP on the wrong path — all *existed*. Every guard carries a dollar
   defeat/acquire price read from live state; a guard priced below what it protects is a finding.
   (`CORE.md §4`)
3. **The reachability gate was excluding real bugs.** "Unprivileged" → **acquirable** (privilege is
   fine if it's cheap to acquire, priced). "Atomic/no cross-block" → **capital at risk** (time,
   waiting, precomputation, a month-old seeded message are all free). (`CORE.md §7`)
4. **Atomicity and the unread surface get their own passes.** What survives a half-failure, what the
   atomic unit actually is on this substrate (tx vs message vs instruction vs nested context), the
   other chain's side, the shared framework's unapplied advisories, the `_v92` beside the `_v96`.
   (`CORE.md §5 D/F`)
5. **Effort is mandatory, the conclusion is free.** Denominators (count before you dismiss), a kill
   quota (three cited kills per lens per seam), and a mandatory Null Report on any clean verdict —
   instead of the "there's definitely a bug here" lie, which manufactures false findings. (`CORE.md §0,§5,§7`)

## On your two ideas

- **The "dead run" ("there's a bug, find it").** Don't. It converts precision into recall and you'll
  get a confident false positive dressed as a critical every time. The real problem it's aiming at —
  under-investment when the auditor expects nothing — is solved by the denominators + kill quota +
  Null Report, which force the effort without forcing the conclusion. Full reasoning in
  `ANALYSIS.md §4`.
- **Testing against the old build.** Right instinct, built out in `eval/`. The catch is
  contamination: the model may recall the answer instead of deriving it, and you can't tell from the
  answer. So `eval/` scores the *path* (the intermediate observations), flags runs that name the
  incident before making any observation, and includes clean controls to measure false positives.
  `eval/README.md` has the method; `ANALYSIS.md §5` has the reasoning.

## Important

`ANALYSIS.md` names specific incidents on purpose — it's the reviewer's rationale. **Never put it in
an auditing agent's context.** An auditor that has read it hunts for those eight incidents; the whole
point of the rewrite is that the next exploit is a different one at the same *kind* of seam. The
CORE + modules deliberately teach the shapes without naming a single incident.
