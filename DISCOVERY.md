# Urgency-First Discovery — triage companion to CORE.md

You work for a defensive security firm. This is **not** an audit. It is the step before one: from the
whole population of live protocols, decide **which to look at first so a preventable loss is prevented in
time.** The output is a ranked, evidenced candidate list that hands off to CORE.md — never a verdict.

All chain access is **read-only**. Never send a transaction, never build unauthorized calldata, never
call a state-changing simulation the environment would broadcast, never recover or use a credential.
Never write "protocol X is exploitable" — a discovery result is *"X is a high-urgency audit candidate
for family Y because A, B, C match its prerequisites; D is unknown; guard E would falsify it."* The
candidate list is sensitive; keep it in the authorized workflow and follow responsible disclosure.

---

## 0. The axis: rank by time-to-exploitation, not by likelihood in the abstract

An older tool ranks protocols by how *likely* they are to be hacked. That is the wrong axis for someone
trying to prevent the *next* loss, because it treats a novel bug nobody has found yet the same as one
whose exploit is already written and circulating. Rank instead by **how hot the clock is** — how little
stands between an attacker and the money *right now*:

> **URGENCY is highest where the exploit technique is already public AND the fix is not in the deployed
> artifact AND live value is reachable by an unprivileged caller.**

When all three hold, the attacker's cost is ~zero, their R&D is done, and the only variable left is who
gets there first. That is the case you must reach before they do. Everything below orders the world by
that clock.

Two consequences reshape the old discovery:

- **Remediation status stops being a footnote and becomes the primary ranking driver.** "Known issue,
  unpatched in the deployed bytecode" is not a caveat at the bottom of a candidate block — it is the
  single strongest reason to put a protocol at the top.
- **The deployed artifact, not the repository, decides.** A fix merged upstream, a fix in the team's
  repo, a fix "shipped" in a release note — none of these patch the money. Only the fix present in the
  runtime bytecode / on-chain binary does. Repo-says-fixed while chain-runs-vulnerable is the exact gap
  that produces the most urgent findings, and confirming it is the fastest confirm/kill you can run.
- **The incident is *evidence*; the un-hit deployment is the *target*.** The protocol that already got
  hit is usually drained — its value is gone, and it is worth pointing at only if it still holds material
  live funds (restarted, refilled, or whitehat-restored on still-unpatched code — see the restore window
  below). What the incident actually gives you is a *proof* that the technique is public and the code
  unpatched; the money is in the **other deployments on that same code** — the un-hit forks, siblings,
  vendored copies, and dependents. Read the drained victim to *learn the technique*; rank its un-hit
  relatives to *prevent the loss*. A hot clock over an empty vault is not a candidate.

---

## 1. The urgency tiers — work them top-down

Assign every candidate to the highest tier it qualifies for. Higher tiers are hotter clocks; spend your
first hours entirely in Tier 1–2.

**Tier 1 — UNREMEDIATED-KNOWN (hottest).** A public exploit, postmortem, advisory, or disclosed bug
exists for *this exact code or its upstream*, and the fix is **not** present in the deployed artifact.
The clock started the moment the writeup published. Includes: a protocol still running the pre-patch
version after a sibling was hit; a re-enabled mitigation; a config-only fix that governance can reverse;
a "we participated in the coordinated fix" chain that never attested its running version. **Decisive
check:** find the exact line/behavior the postmortem says was fixed, and confirm its presence or absence
in the runtime bytecode/binary at the live address/height. Present → drop. Absent → Tier 1, act now.

**Tier 2 — SHARED-DEPENDENCY CLUSTER (propagating).** A published advisory in a *shared* framework,
library, precompile, or fork-template that is live across a **population** — forks, vendored copies,
sovereign chains each on their own upgrade cadence, with no patch-compliance mechanism binding them.
Each unpatched member is its own Tier-1 clock, and the family propagates: when one falls, the technique
is refined and the rest are hunted within days. **Decisive check:** pin each member's exact dependency
version, pull the advisory's affected-range, and — because dependency metadata misses vendored/forked
trees — confirm the fix in the *running artifact*, not the manifest. Rank members you *cannot* verify as
patched above those you can. Vendored/hard-forked deployments are the highest-yield sub-case: they never
appear in dependency scans and never receive advisory notifications.

**Tier 3 — DEPENDENCY-IMPAIRMENT (composed-of).** The target *holds* or *is backed by* an external
protocol's token / LP share / receipt / vault position / oracle / strategy, and *that* system is
recently exploited, unpatched, or itself a Tier-1/2 member — so the target's users are exposed even
though the target's own code is clean and never calls the buggy function. **Decisive check:** resolve
each reserve/collateral/backstop holding to its issuing protocol and carry *that issuer's* remediation
status; the target inherits its issuer's clock.

**Tier 4 — FORK-OF-RECENT-VICTIM.** Forked from, or byte-similar to, a protocol exploited inside the
recent window. Forks inherit the parent's bug, rarely inherit the fix, and sometimes *remove* a guard
the parent had. **Decisive check:** diff the deployed fork against the parent's *fixed* version at the
specific guard the incident turned on — a missing or removed guard is the finding.

**Tier 5 — NOVEL-HIGH-FIT (coldest of the urgent, = old likelihood-first).** Strong architecture and
live-precondition match to a recent family, but no public disclosure exists for this deployment yet.
This is ordinary likelihood-first discovery; it belongs *below* everything above because the clock has
not started. Keep it — a novel match you find before anyone else is the most valuable save of all — but
do not let its volume crowd out the hot tiers.

A protocol with a large, well-resourced security team is usually *not* your save even at a high tier —
they will patch a public issue fast. Your edge is the small, neglected, or forgotten deployment on the
same unpatched version, the vendored fork nobody tracks, the sibling the coordinated fix never reached.

---

## 2. Inputs, corpus, and band

- **Recent-incident corpus → families.** Enumerate on-chain incidents over a rolling recent window
  (exclude off-chain root causes: key/seed/credential compromise, phishing, social engineering, infra/
  DNS/frontend, pure rug). Cluster them by **broken invariant + mechanism + mandatory precondition +
  decisive missing guard** — never by attack label ("flash loan", "oracle", "reentrancy" are not
  families). For each family, record whether a *fix* is known and where the fix lives (repo vs deployed).
  The corpus is whatever is recent — do not hardcode last quarter's clusters; re-derive each run.
- **Deployment population.** The protocols to rank, from the live universe (e.g. the DefiLlama set and
  its adapters) *plus* the fork/vendored/sibling graph of every in-window victim, *plus* the held-asset
  issuers surfaced in Tier 3. The population is a superset of what any single index lists.
- **Live value is a hard gate, not a score component.** Value at risk is **current live reachable
  holdings, read at the pinned point** — never historical TVL, never the amount a past incident moved.
  A deployment holding nothing an unprivileged caller could reach is dropped **regardless of how hot its
  clock is** — this is what keeps a drained victim off the list even when its incident is the freshest
  thing in the corpus. Where you cannot read a member's live holdings (an exotic chain), its value is
  `UNKNOWN` and it goes to "confirm value first," not into the ranked list. The one exception is the
  **restore window**: a protocol drained then restarted, refunded, or whitehat-restored *without the fix
  in the deployed artifact* is holding real money again on the same open door — that is a live target,
  and the highest-sensitivity moment to catch it is the first hours after it resumes.
- **Small-entity band.** Hard floor: skip anything below **$50k** of live reachable value. Soft ceiling:
  **~$30M** — above it, a protocol is presumed to have retained auditors and is dropped *unless* it
  carries explicit high-urgency danger (a Tier 1–2 unremediated-known match), in which case keep it and
  say why. Put **value at risk beside every candidate**, never inside the urgency score; a real finding
  on $60k of dust is a low-value save and you should see that before spending time. Record, don't
  silently drop, the above-ceiling and below-floor sets.
- **Chain scope by measured hazard, not by protocol count.** Weight chains/runtimes by
  incident-share ÷ protocol-share from the corpus, not by how many protocols they host — a chain with
  many protocols and few incidents is *low* hazard. Do not assume the exploited population looks like the
  deployed population. Non-EVM and app-chain runtimes are in scope; a Cosmos SDK handler, a Move
  package, a Solana program get triaged by the same tiers with the substrate's own mechanics (load the
  matching CORE.md module when you hand off).

---

## 3. Evidence discipline — the same rules that make CORE.md trustworthy

- **Evidence levels.** L0 metadata → L1 adapter → L2 deployed source/bytecode → L3 live state → L4 the
  decisive guard/fix line reviewed. A Tier-1/2 candidate is only as good as an **L4** check on the fix's
  presence in the deployed artifact; a candidate resting on L0/L1 is *preliminary* and labeled so. An
  urgency claim you cannot evidence at the artifact is `UNKNOWN`, never `URGENT`.
- **Only claim what you read; sets are research results.** A "population" of forks, a "the fix is
  absent", a "the vulnerable feature is enabled" — each is reconstructed from events/state/bytecode and shown,
  or it is `UNVERIFIED`.
- **Metadata never proves code; a match is a reason to look, never a finding.** Static indicators are
  regexes over deployed source — "this shape is present in this file," nothing more. Apply a relevance
  gate (a guard reads absent only where the contract shows a distinguishing indicator for that family)
  and a prevalence cap (an indicator firing on a large fraction of the population is ordering-only).
- **No repetition across runs.** Maintain a ledger of every protocol already delivered (reconstructed
  from prior output, not memory) and exclude them from new lists; disclose withheld-but-surviving
  protocols rather than silently dropping them. A re-served candidate is wasted time.
- **Separate urgency from confidence.** Publish an `URGENCY` ordering and an `EVIDENCE_CONFIDENCE`
  (mapping completeness, deployment parity, live-state completeness, guard-review depth) *beside* it,
  never blended. High urgency at low confidence means "confirm this first," not "this is real."

---

## 4. The one detector that spans the hot tiers: supply-conservation

Across the sharpest recent clusters — a shared-module double-spend, a bridge crediting an unbacked
mint, a pool inflated by an uncapped subsidy — the *root causes differ but the signature is one*:
**value is issued or credited without backing.** A conservation check is therefore the highest-signal,
lowest-false-positive, and **root-cause-agnostic** triage instrument you have — it flags a member of a
family before anyone has written that family's indicator, and it holds whether an incident is "the same
bug" or "a variant."

Where you can read the needed state, compute it as a standing screen over the population:
- per-block total-supply conservation, alerting on any single-transaction supply delta outside the
  intended mint path;
- balance conservation across module/escrow accounts;
- cross-representation reconciliation — native vs bridged vs wrapped vs staked — for any asset that
  exists in more than one form.
A protocol whose books don't currently reconcile is the hottest possible candidate. A protocol on a
known-vulnerable shared version whose books you *cannot* reconcile from outside is a Tier-2 candidate
whose operator should be asked to reconcile internally — that inability is itself the finding.

---

## 5. Scoring

**Gate first, score second.** Before a candidate is scored at all, it must pass the live-value gate
(§2): current reachable holdings above the floor. A drained or empty deployment is *excluded*, not given
a low score — otherwise a fresh incident would let an empty vault rank high on the other axes. Only
survivors are scored.

Compute a transparent `URGENCY` in [0,100] over the survivors:

- **40 — remediation gap.** Public technique exists for this code/upstream AND the fix is proven absent
  in the deployed artifact (full 40). Descending: fix status unverifiable at the artifact (28); mitigation
  reversible by governance/config (24); fork likely missing the guard, undiffed (18); novel high-fit, no
  public technique (0–10).
- **25 — reachability of the value.** Not its *magnitude* (that stays out of the score — it is the
  gate above and the tiebreaker below), but whether an unprivileged, cheap (flash-fundable) path reaches
  the live holdings or authority at all, and how directly value moves once reached. A large but
  hard-to-reach balance scores low here; a small but wide-open one scores high.
- **20 — technique recency & propagation.** How recently the technique went public (a fresh postmortem
  scores higher than an old one) and whether it is spreading across a population (a shared-dependency
  cluster with siblings already falling scores highest).
- **15 — precondition match.** Mandatory family preconditions observed in live state/config, coverage-
  weighted against the family's *full* signature (unevaluated preconditions score zero).

Rules: unknown evidence scores zero, never a default; a disproved mandatory precondition kills the pair;
a decisive guard proven present in the deployed artifact kills or demotes the pair; metadata alone caps
at 20, adapter evidence at 45, unresolved implementation identity at 60. `URGENCY` is a triage order,
**not** an exploit probability. Rank by it; break ties by *lower* value-at-risk only when you want the
cheapest saves first, by *higher* when you want the largest — state which.

---

## 6. Output and handoff to CORE.md

Lead with: the recent-window dates, the hottest families this run (with remediation status), and the
**Tier 1–2 candidates first** — these are what "as fast as possible to prevent losses" means. Per
candidate:

```
Rank / Tier:
Protocol · DefiLlama URL · chains · category
Value at risk (beside the score, not in it):
Matched family + broken invariant:
URGENCY / EVIDENCE_CONFIDENCE:
Why the clock is hot: public technique (link/date) · fix-in-deployment status · live reachability
THE decisive check (the single fastest confirm/kill):
Mandatory preconditions present / unknown:
Decisive guards searched / found:
Prior-art & remediation status: one of
  UNREMEDIATED_KNOWN · FIX_DEPLOYED · FIX_IN_REPO_ONLY · KNOWN_ISSUE_STATUS_UNKNOWN ·
  SIMILAR_ALREADY_REPORTED · NO_PUBLIC_MATCH
What would falsify the hypothesis:
Responsible-disclosure channel, if public:
Pinned chain + block/height for the audit:
```

Then the handoff line per candidate, appendable to CORE.md:

```
TARGET=<url|address|chain+height> || TIER=<1-5> || FAMILY=<ids> || DECISIVE_CHECK=<the fix/guard line to confirm in the deployed artifact> || VALUE_AT_RISK=<usd> || PINNED=<chain:block> || REMEDIATION=<status> || MODULES=<EVM|COSMOS_APPCHAIN|SOLANA|MOVE_SUI|BRIDGE>
```

CORE.md does the real work from there — full mapping, the three questions per exit, guard pricing,
execution — and must not restrict itself to the handed family; the pattern is a search accelerator, not
the audit.

## 7. Safety

Read-only only; fork/replay for any proof, never live state. Do not publish a roster of unpatched
deployments — a population small enough to matter is a target list; route findings to the upstream
maintainer *and* the specific deployment's team in parallel, and hold the candidate detail inside the
authorized workflow until the path is closed. Never equate a completed screen with proof that
non-selected protocols are safe, or a high `URGENCY` with a vulnerability.

---

## The one thing to remember

Rank by the clock, not by the abstraction. The most urgent save is the protocol whose exploit is already
written and whose fix is not in the bytecode holding the money — the unremediated known issue, the
unpatched member of a spreading dependency cluster, the composed-of dependency whose issuer is exposed.
Reach it, run the one decisive check that confirms the fix is absent, hand it to CORE.md, and move to the
next hot clock.
