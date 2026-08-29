# Orientation — how this project got here and how to think about it

**Read this first if you are picking the project up.** It is the linear story of what we built, why,
what went wrong, and how the prompt got better (and where it could get worse). It is written to be
understood without having lived the conversation.

**Wall warning (same as `ANALYSIS.md`):** this file names real incidents and discusses the method's
weak spots. It is **reviewer-side**. Never hand it, `ANALYSIS.md`, or the `eval/cases/*.json` answers to
an auditing agent — an auditor that has read them will hunt for those specific incidents instead of
thinking. The things an auditor may see are only `CORE.md` + the relevant `modules/*.md` + a target.

Where to fetch detail rather than trust this summary:
- **Per-change reasoning, with evidence:** `ANALYSIS.md` (long; the changelog-with-rationale).
- **Exact incident forensics / eval answers:** `eval/cases/*.json` → `answer_for_grader_only` (grader-only
  fields), and the ground-truth write-ups the operator pasted into the conversation.
- **The method itself, current:** `CORE.md` and `modules/*.md`. Always read the live file; do not trust a
  quote here if it conflicts.
- **Objective timeline:** `git log --oneline` on branch `claude/defi-audit-prompt-testing-e5aohv`.

---

## 1. What the project is, in one paragraph

A two-file-class system for auditing DeFi deployments for theft: **`CORE.md`** carries a
substrate-agnostic *method* (how to find the way an unprivileged stranger takes value or control), and
**`modules/*.md`** carry substrate *mechanics* (EVM, Cosmos app-chain, Solana, Move/Sui, cross-chain
bridge). A real run is `CORE.md` + the right module(s) + a target (a DefiLlama link, an address, a
chain+height+binary, or a triage handoff line). Everything else in the repo — `eval/`, `ANALYSIS.md`,
`DISCOVERY.md`, this file — is scaffolding, record, or a de-scoped companion, **not** the product.

## 2. Where we started, and the original flaw

The operator's starting prompt effectively **read contract addresses and checked them** — it treated
"the system" as the set of deployed contracts. But in the incidents that motivated the work, the money
did **not** leave through a bug inside a single contract. It left at a **seam** — a boundary where one
component restates a fact another produced (an oracle read, a cross-chain message, a governance edge, a
backing token, a batched message). A contract-by-contract read clears every component in isolation and
still misses the exploit, because the defect is a property of a *relationship*, not a contract. That is
the whole reason the rewrite exists. (The eight-incident calibration table and the "eight for eight, the
defect lived at a seam" argument are in `ANALYSIS.md §1`.)

## 3. The system as it exists now (file map)

- **`CORE.md`** (~855 lines) — the method. §0 mandate (effort mandatory, conclusion free) · §1 the spine
  (the **exit** object + three questions: Q1 authorization/identity, Q2 amount/backing, Q3 does-the-check-
  hold) · §2 the nine registers (ledger on disk) · §3 evidence rules (the deployment is the system) · §4
  **guard pricing** (price every guard in dollars from live state) · §5 seven lenses + the fleet pass · §6
  execution (fork/replay, warp, PoC) · §7 kill / recompose / argue-the-other-side / Null Report · §8 what
  counts + the **reachability gate** (Acquirable · Live · Cheap) + severity · §9 output + self-checks · §A
  intake (deriving the system from each input type).
- **`modules/`** — `EVM.md`, `COSMOS_APPCHAIN.md`, `SOLANA.md`, `MOVE_SUI.md`, `BRIDGE.md`. Substrate
  mechanics only; they are allowed to be substrate-specific but must teach shapes, not incidents.
- **`CORE.v1.md` / `v2.md` / `v3.md`** — archived earlier versions, kept for diffing. The live method is
  `CORE.md`.
- **`DISCOVERY.md`** — an urgency-first triage companion that scans many protocols and emits a "handoff
  line" for `CORE.md` to audit. **De-scoped** during the main work (the operator said to focus on
  CORE+modules). CORE §A still accepts its handoff line as a first-class input.
- **`ANALYSIS.md`** — the reasoning record: every substantive change with its evidence and the rejected
  alternatives. Reviewer-side.
- **`eval/`** — the blind test harness (see §8 below).
- **`README.md`** (root and `eval/`) — short entry points.

## 4. The method in one screen (so you can reason about changes)

Every exploit in this class is the same event: **the system parts with value, or issues a claim on
value, when it shouldn't.** So the unit is the **exit** (any path value leaves by *or is issued by* — a
transfer, redemption, liquidation, standing approval, **and every mint/credit/wrap/share-issuance**).
Exits are a small closed set; enumerate them, then ask three questions of each — Q1 (is the right party
acting on the real thing), Q2 (is the number right and is what's issued backed), Q3 (does the guard
enforce the invariant, or pass while checking the wrong thing). Numbers/identities/checks reach exits
through **seams**; the lenses (A staleness, B forgery, C miscomputation, D atomicity, E identity/
distinctness, F boundlessness/composition, G check-that-passes-but-doesn't-hold) are the detection
toolkit for the three questions. Three honesty mechanisms carry the weight: **denominators** (count a set
before dismissing it), the **kill quota** (a written, code-cited attempt to break each candidate), and
the **Null Report** (a clean verdict must name where you'd bet you're wrong). Then **execute** (fork,
warp, build the PoC) — reading is not proof. Report only what you proved, and if that's nothing, say
where you're wrong.

## 5. The journey, linearly (problem → fix)

**v1–v3 (`b91ad52`, `0e9b4ca`, `47a7f79`) — build the method.** Rewrote from contract-centric to
seam-centric (v1); unified everything under one spine (v2, added the Move module and a precision lens);
rebuilt the spine into *three questions per exit* from a full 6-month incident corpus (v3). This is where
the method's bones were set.

**v4 (`94c700b`, modules `929e072`) — calibrate against external review.** An outside review caught that
the prompt carried a **base-rate prior** ("most systems have a live path" / "expect to find something").
That is corrosive: it manufactures false positives. Cut it. Fixed the governance and time-warp handling,
and **stripped incident-steering from the modules** (teach shapes, not "look for X"). The governing rule
from here on: *effort is mandatory, the conclusion is free.*

**v4.1 (`63ddf8b`) — scope what the system is made of.** Added the composed-of / backed-by obligation:
a protocol can be drained through a token/vault-share/LP position it *holds* as backing, even when its
own code is flawless. Follow each holding into its issuer.

**DISCOVERY + eval harness (`94c00b6`…`4885e22`).** Built the triage companion and, more importantly, a
**blind evaluation harness** — a way to test whether the method actually catches real recent incidents
when it cannot see the answer. This is what turned opinion into measurement. DISCOVERY was then largely
set aside to focus on CORE+modules.

**The crisis: 14 clean runs.** Run blind against a real advisory family (Cosmos-EVM precompiles), the
method returned "No verified finding" **14 times**. Diagnosis: it had quietly become an **advisory
scanner** — receive a known-bug hypothesis, pin the version, check whether the affected surface is live,
answer "no," stop. That is vulnerability scanning, not auditing; it can never find a novel bug because it
never looks for one. Fix (`0a20820`, `18595a0`, `232c6b9`): **restore novel-bug discovery over
advisory-checking** — demote advisory-checking to cheap hygiene whose result changes nothing about the
obligation to audit every exit; read the fleet diff *both ways* (a removed guard *and* newly-added code);
close the gap between *surfacing* a defect and *proving* it.

**Real-incident cases (`3a2e5e3`, `9a923c1`, and 10/11).** Added blinded cases for real recent drains —
**Term Finance** (governance capture, ~$8.5M) and **MayaChain** (batched-message drain), plus CometDEX
(assumed-distinctness) and a $34M vault case. Running these exposed the next, deeper problem.

**The real problem was classification, not effort.** The auditor *was* finding the structural defects —
and then filing them where they die: an "open question," an "UNVERIFIED" acquisition cost, "uncovered
exposure," an "incomplete" verdict. A diagnostic (`f8cec93`) added an effort-nudge to the harness and it
**didn't help** — proving the blocker was not budget. So the fix had to be about *classification*, and it
belongs in CORE, not the rig.

**v6 arc — make an established defect a finding.**
- **v6 (`1214cb1`):** an established structural defect (a guard priced below what it protects and shown
  acquirable; a value an exit trusts shown stale/manipulable; issuance with no backing) is a **finding the
  moment its preconditions hold — with or without the PoC**, carried `UNPROVEN`. Every "I couldn't build
  the beneficiary path" resolves into exactly one of two: a cited line closes it → *killed*; else →
  *`UNPROVEN` finding*. Never a silent third.
- **v6.1 / v6.2 (`0c30d84`, `7b4c4ba`):** de-normalize "open questions" (they're for genuine external
  blockers, not deferred self-work); `findings.md` carries **every** finding incl. `UNPROVEN`; findings —
  not open questions — take the slot above the verdict.

**The "remove, don't stack" correction (`bb6e6e4`).** v6.1/v6.2 had been applied as long *additive*
blocks (and one hard-coded a governance-specific PoC recipe). The operator's principle: *longer ≠ better;
control behavior by removing as much as adding; the machinery already existed and was overridden — make
it bind, don't pile on.* So we **reset `CORE.md` to v6 and reapplied the same intent surgically** (net +6
lines, general, no named technique), instead of stacking. This is one of the most important process
lessons in the whole project.

**§4 acquire-price is fork-executable (`fe1590c`).** A run priced only the open-market route to
governance and stamped the deposit-to-votes route "UNVERIFIED." But that price is an *action the fork can
perform* — deposit and read whether the privilege followed. Added one sentence: an acquire-price the fork
itself can pay is never `UNVERIFIED`. (This one was run through a diagnose-then-refute workflow before
landing; a broader label-agnostic version was tried and *rejected as padding*.)

**Generalize (`b59e17a`).** Swept CORE + modules for anything pointing at an *exact* finding (Maya's
`SetPool`-before-`Send` / `_v92`/`_v96`, past-tense 2026-incident narrations, frequency-steers) and
turned each into a general shape. The prompt is a general tool; the incidents are only tests.

**Environment ownership (`176333a`).** Fresh runs (Cronos, Canto) accepted *self-fixable* environment
failures as walls — "Go too old," "modules 403 from the proxy," "public RPC stale." The auditor has full
rights over its environment. Fix: **the environment is the auditor's** — update the toolchain, set the
proxy, stand up its own node, pick another endpoint. A blocker is legitimate only if *neither* the auditor
nor the operator can lift it (a refused credential, private source nobody has).

**Cheap gate vs. reward (`a7384c1`).** The reachability gate's "Cheap" condition read too harshly — a
naive reading could exclude a small-outlay, high-reward attack (a governance capture funded with a few
ETH that takes millions). Clarified (not loosened): cost is weighed *against the reward*; capital the
exploit itself returns is cheap; what still fails is an outlay *both unrecoverable and large against the
take*.

## 6. How our understanding shifted (initial view → where it landed)

1. **"The system is the contracts."** → The system is the deployment **plus its seams, priced guards,
   backing tokens, and off-chain dependencies.** Clearing components is not an audit.
2. **"Find bugs by checking known advisories."** → Advisories are hygiene; the audit is *understanding
   behavior and interrogating every exit*. A clean advisory sweep says nothing about the deployment's own
   code.
3. **"No finding = clean."** → No finding ≠ clean. A killed hypothesis is not an audit; the **Null
   Report** is mandatory on a clean verdict; **`UNPROVEN` findings are first-class**, not footnotes.
4. **"It's not finding things because it needs to try harder."** → It was *finding* them and
   **mis-filing** them. The fix is classification (make the defect land as a finding), not effort.
5. **"A longer, more detailed prompt is a better prompt."** → Length competes for the auditor's
   attention. Remove and rewrite as readily as add; a rule the auditor already has and ignores is not
   fixed by repeating it louder — it's fixed by making it *bind* or by removing the escape hatch.
6. **"Success = weaponizing the full exploit chain."** → Success = **finding the defect that, if fixed,
   prevents the hack**, plus honest calibrated reporting (PROVEN / `UNPROVEN` / incomplete / clean+Null).
   Maya's run that found the root clobber and gave the exact fix *would have prevented the hack* even
   though it never built the 6-step drain.
7. **"Open questions / blockers are normal outputs."** → They are only for genuine external blockers the
   auditor cannot lift with its full environment rights. Anything it (or the operator, by reconfiguring)
   could resolve, it must resolve.

## 7. What makes the prompt better — and what makes it worse

**Levers that made it better (keep these load-bearing):**
- Seam as a first-class object; the three-questions spine; enumerating exits as a closed set incl.
  issuance.
- **Guard pricing in dollars from live state** — "guarded" is not a finding-killer; "costs less than it
  protects" is.
- Denominators + kill-quota + Null-Report — they make effort visible and the conclusion honest *without
  telling the auditor the answer*.
- Execution-first (fork, warp, PoC); reading is not proof.
- `UNPROVEN` findings first-class + `findings.md` carries them; no false-cleans.
- Open questions reserved for external blockers; the environment is the auditor's; the Cheap gate weighed
  against the reward.
- Teaching **shapes, not incidents**; the composed-of/backing scope.

**Things that make it worse (the anti-patterns we fought — a change is suspect if it reintroduces one):**
- A **base-rate prior** ("expect a bug") — manufactures false positives. Cut in v4; never re-add.
- **Naming incidents / techniques** — the auditor hunts for the named bug instead of thinking. Leads by
  hand.
- **Padding** — length for its own sake; every addition should earn its attention or replace something.
- **Advisory-scanning** — checklisting known bugs in place of auditing exits.
- **Per-case rules** ("if governance is in open questions, make it a finding") — must be general or not at
  all.
- **Additive stacking** — piling paragraphs to fix a rule the auditor already overrides; prefer rebuild/
  remove.
- **Letting the eval scaffold do the method's job** — anything the auditor needs on a *real* run must live
  in CORE/modules, because a real run has no `START_HERE`.

## 8. The eval harness (and what is eval-only)

`eval/` runs the method **blind** against real historical incidents and scores it. Key pieces:
- **Blinding is a whitelist.** `run_case.sh` ships the auditor only `id`, `substrate_modules`,
  `blinded_brief` (a generic *scope*, e.g. "an EVM strategy-vault with a governance role — find how an
  unprivileged caller extracts value, or establish there is none"). The operator-only fields (`class`,
  `note`, `must_reach`, `answer_for_grader_only`) never reach the auditor; a leak-check screens for answer
  markers. Proof it's genuinely blind: a run once found a *different* real bug than the case targeted —
  impossible if the setup leaked the answer.
- **The grader (`grade.py`) reads `transcript.txt`, not `findings.md`.** It scores **PATH** (did it hit
  the `must_reach` steps), **DERIVED** (no early incident-naming), **PROVEN** (a fork/PoC/assertion). Its
  signatures are **coarse** — they false-positive (e.g. "slash" matching an uncapped-subsidy step) and
  under-credit; **read the transcript content, don't trust the number.**
- **`START_HERE` / the stage scripts are eval-only.** They add blind rules, hand over the target, and set
  output-file names — none of which a real run needs (a real run wants the blinding *gone* so the auditor
  can use the web, prior audits, DefiLlama).
- **Block heights are eval-only.** Cases pin to `exploit_block − 1` so the test runs against *pre-hack*
  state (the only way to score "would it have caught it"). **CORE/modules hard-code no block number and
  never tell the auditor to audit a past/hacked state.** A real run pins the **current head** purely for
  read-consistency; the reachability gate is entirely about "the money is there *now*." (Verified: zero
  block numbers and zero "pre-exploit/historical" framing in CORE or modules.)
- **Two rig fixes worth knowing:** in a proxied sandbox `anvil` ignores `HTTPS_PROXY`, so its fork egress
  is blocked (403 from istio) — `rpc_forward.py` is a loopback curl relay `stage_real.sh` auto-starts to
  route the fork through. And a halted-then-patched chain's live head / current version is *post-fix*, so
  `stage_*` START_HERE pins reads to the historical height/version (the general version-at-pin discipline
  now lives in the Cosmos module too).
- **`selftest.py`** proves the harness plumbing; `controls/` are negative cases.

## 9. How to run it for real

Load `CORE.md` + the module(s) for the substrate, then hand a target and go — e.g. *"Follow this method.
Target: `<DefiLlama link | address+chain | chain+height+binary | triage handoff line>`. Audit it, produce
the report and `findings.md`."* CORE §A derives the deployment, pins the current head, stands up a fork,
and runs. Do **not** paste `START_HERE` or any `eval/` scaffolding; it's the test rig. Make sure the
environment has (or can install) the tooling and RPC/API access — the auditor now treats that as its own
to set up.

**A richer "triage handoff line" input** (from `DISCOVERY.md`, or hand-written) improves *efficiency*
(front-loads scope: target, module, pin, and a cheap first confirm/kill). CORE §A treats `TARGET`/
`PINNED`/`MODULES` as scope but `FAMILY`/`DECISIVE_CHECK` as *a hypothesis to test first and then set
aside* — because a handed family can be wrong (a real handoff labeled the Term target `ORACLE-STALE`
when the actual bug was governance). Effectiveness stays positive only while the auditor obeys "set the
family aside and audit every exit regardless."

## 10. Known remaining weaknesses (open threads)

- **Run-to-run variance is the main weakness.** On the same target the auditor sometimes lands the
  headline defect and sometimes a lesser real one. Mitigate by running 2–3× and unioning, or fanning out.
- **It doesn't reliably build multi-step *headline* exploits.** On Term it repeatedly missed the
  **governance permission-loop** (`DELAY.owner()==ROLES`, Role 1 → DAO → the DAO enables itself as a
  delay-exempt module and bypasses the timelock) — a *cycle in the authorization graph* invisible to
  per-function reachability tests. On Maya it found the root clobber but usually not the full uncapped-
  subsidy → pool-inflation → LP-drain monetization. Both misses are **execution/thoroughness**, not
  missing doctrine (CORE already says to trace every address that can call the delay's setters, and the
  module already describes the uncapped-subsidy shape). The one *candidate* general addition still open:
  make the auditor **build the control/authorization graph** the way Lens F already forces it to build the
  *state* dependency edge list, then search for a path from an acquirable outsider position to a
  fund-moving action — the "recompose pass forced to chase the graph." Not yet added; would need the
  diagnose-refute check first, and it must not become padding.
- **Occasional arithmetic/severity errors** (a Maya run sized exposure at ~$424M vs a real ~$8M). Sanity-
  check headline dollar figures against known TVL.
- **Named-not-run.** The auditor sometimes names a fork-doable settling action instead of running it. The
  environment-rights and fork-executable rules push against this; watch whether they bind.

## 11. The calibration incidents (hints; fetch detail from the cases / write-ups)

Do not expand these into the prompt. They are only here so you know what the tests are aiming at; the
full detail lives in `eval/cases/*.json` (`answer_for_grader_only`) and the operator's pasted write-ups.
- **Term Finance (case-12)** — governance capture via a *permission loop* that bypasses a 7-day timelock;
  ~$8.5M. Root cause is authorization-graph, not oracle.
- **MayaChain (case-13)** — a single batched `MsgDeposit` clobbers a shared voter, driving a false
  theft-detection that pays an *uncapped* slash subsidy into a thin pool the attacker then LPs into and
  drains; ~6 chained bugs. Root cause = the per-message-vs-per-tx identity clobber; the fix at that one
  line prevents the whole chain.
- Older cases 01–11, by their file slugs (read each case's `answer_for_grader_only` for the real
  specifics; don't trust a mechanic guessed from the name): `shared-framework-precompile`,
  `governance-capture`, `guard-on-wrong-path`, `bridge-forged-message`, `solana-account-substitution`,
  `precision-rounding`, `proof-verifier`, `mis-specified-verification`, `conservation-unbacked-mint`,
  `assumed-distinctness`, `vault-spot-valuation`. The structural *shapes*, not the names, are what CORE
  teaches.

## 12. Operational / sensitive notes (hint only)

- **Runtime chain access** uses an operator-provided archive RPC key (Alchemy) passed on the command line
  at stage time. It is **never committed** and must never be — before any commit, verify no key is in the
  tree. If you need it, ask the operator for the current key; do not reconstruct or store it.
- **Chain reads are read-only / fork-only.** Never send a transaction to a public network; fork only.
- **Cosmos app-chains are not anvil-forkable** — audit from the pinned binary/source + live query
  endpoints at the height; PoC via the chain's own Go test harness.

## 13. Fast pointers

- Method, current → `CORE.md`; substrate mechanics → `modules/<substrate>.md`.
- Why a change was made, with evidence → `ORIENTATION.md` (this file) for the arc, `ANALYSIS.md` for the
  per-change detail.
- Exact incident answers → `eval/cases/*.json` `answer_for_grader_only` (reviewer-side).
- Run it for real → §9 above. Run the eval → `eval/README.md` / `eval/RUNBOOK.md` and the `stage_*.sh`
  usage lines.
- Timeline → `git log --oneline` on `claude/defi-audit-prompt-testing-e5aohv`.
- The single most important process lesson → §5 "remove, don't stack," and §7's anti-patterns.
