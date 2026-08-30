# Module — Generic / unfamiliar substrate

Load with CORE.md whenever the target runs on a chain or VM that has **no dedicated module here** (or
alongside a dedicated one, for a property it doesn't cover). This module does not describe one chain — it
is the method for auditing a substrate whose mechanics you do not have memorized. The recurring critical
on an unfamiliar substrate is **importing the semantics of a chain you already know** — assuming this
chain's atomic unit, account model, arithmetic, or authorization works like your default. CORE names
that blindness as one of the most reliably exploited patterns; here it is the *first* thing to defeat. So
the opening job is not to audit — it is to **establish, from the substrate's own spec and its live
behavior, the handful of properties CORE's three questions rest on.** Assume nothing; confirm each and
write it to the ledger (register 1 / anomalies). A property you assumed instead of read is the seam.

## Characterize the substrate first — read this before enumerating exits
For each, find the answer in the chain's own documentation *and* confirm it against live behavior, then
record it. These are the parameters CORE's method is written against; a wrong one silently invalidates
every later step.
- **State & account model** — what holds value and state: accounts, resources/objects, UTXOs, cells, a
  global key-value store? How is a balance represented and updated, and can a caller *create, alias, or
  substitute* the thing that holds it — a look-alike account, a self-owned store, a counterfeit asset
  handle? (Feeds Q1 identity, Lens E.)
- **The atomic unit** — what commits or rolls back as one indivisible step: the transaction, a message,
  an instruction, a call frame, a group/bundle, a block-boundary hook? And what survives a *partial*
  failure? This differs across substrates and is the single most common place a bounded flaw becomes
  unbounded — code written as if the unit were the whole transaction when it is smaller (or larger). Get
  it explicitly, per value-mutating path. (Lens D — the recurring killer everywhere.)
- **Arithmetic & number semantics** — integer widths; does overflow **wrap, abort, or truncate
  silently**, and does that differ between arithmetic ops and bit-shifts/casts (the two often disagree);
  fixed-point/decimal representation and each operation's rounding direction; signed vs unsigned and any
  cast across the sign boundary. Whichever of these is silent is the value-loss surface. (Lens C.)
- **Authorization & signing** — how the caller is authenticated, and whether that authority **carries
  across calls / nested contexts** or must be re-established at each hop; the signature/multisig/threshold
  scheme and its **replay domain** (what binds a signed message to this chain, this contract/version,
  this account, this nonce). An authority evaluated against the wrong account, or a signature valid across
  a domain it shouldn't be, is the exit. (Q1, Lens B.)
- **Execution & composition** — can one transaction call or compose several programs; is there a callback
  / reentrancy into the caller mid-execution; are there fee/gas semantics an attacker can turn (a fee
  refund without a charge, a feeless path, a resource limit that changes what's reachable)?
- **Time, ordering, finality** — what "now" is (height, time, round, slot), reorg/finality behavior, and
  whether **scheduled or block-boundary code moves value with no external caller** (the highest-yield
  unread surface on most chains).

## The cross-substrate shapes — they recur regardless of VM
Map each onto what you characterized above; run the CORE lens named.
- **Atomic-unit mismatch (Lens D).** A value-bearing write that survives the failure meant to guard it; an
  error returned and then logged-and-continued; a nested context's write reflected or double-counted in
  the outer one, so the same balance is spent twice; a batch where an earlier step's write persists when a
  later step fails or clobbers shared state keyed by a common id. State the atomic unit per handler and
  find the code written in the wrong one.
- **Identity & distinctness (Lens E).** Two identifiers asserted to mean the same thing that an attacker
  can forge, collide, or substitute (a counterfeit token/asset handle, a poisoned name→asset mapping, a
  cross-chain counterpart inferred from an attacker-chosen string rather than verified). And the mirror:
  two references the code assumes distinct, handed the *same* one — one leg read while the other is
  written, one leg's debit returned by the other's credit.
- **Envelope-valid ≠ true (Lens B).** A signature/proof/attestation that verifies while the *content* it
  covers is attacker-authored, or narrower than the fields the code then acts on. Verifying the envelope
  is not validating the contents; enumerate every acted-on field and confirm it is inside what was signed.
- **Uncapped issuance / subsidy against a small pool (Q2 unbounded).** A mint, reward, subsidy, slash, or
  redemption amount computed from a figure without capping by the **live balance that must fund it** —
  read both the drawn amount and the funding balance; if the reserve is a fraction of a plausible draw the
  guard is priced at ~0.
- **The native ↔ contract / L1 ↔ L2 / on-chain ↔ off-chain seam (Lens D/A).** Wherever value logic crosses
  two state machines or a trust boundary, each side is usually reviewed as if the other guaranteed
  consistency. That seam is a prime target; audit each side as if the other were hostile.
- **The unread surface (Lens F, attention inversion).** Scheduled / block-boundary / keeper code with no
  external caller and thus no external reviewer; migration / upgrade / init paths; versioned branches kept
  for compatibility and still reachable; old code that still holds mint authority or live approvals;
  anything behind a role dismissed as "privileged" without pricing the role (§4).

## Deriving the system on an unfamiliar chain
There may be no explorer you trust and no source-verification mechanism you recognize. Establish from the
chain's own interfaces, not the repo: the value-holding accounts/objects/modules and their **live
balances** (that is the exit-and-value set); the **live parameters** in effect (from the chain's query
endpoints at the pinned point, never the repo's defaults); and the **full membership** of any set — a
registry, a holder list, a pool/market collection — reconstructed from events or enumeration and shown,
never sampled. One address/object is never the target; grow the system outward through what holds value
and what has authority over it.

## Binding the deployment to source
Use the substrate's own binding: a **reproducible-build hash match** (the on-chain artifact's hash equals
a build of the claimed source at the stated toolchain), the published package bytecode, or a verified-
source facility where the chain has one. Where no binding exists, the **disassembled / decompiled runtime
is what stands in for source** — the repo is a claim about the deployment, not the deployment, and a
version string is the builder's claim, not a property of the artifact. Confirm behavior against the
artifact, and treat "the source says X" as unverified until it binds.

## Guard pricing — substrate-agnostic (CORE §4)
Price every guard in dollars from live state, whatever the VM. On an unfamiliar chain the ones to
re-derive by hand: **who can change a critical parameter and how fast** (governance/admin — its
acquisition cost, and any timelock/veto and whether the veto is real, watched, and ever performed); the
cost to **join any attesting / validating / signing set** (bond or stake to become a quorum member — that
is an acquire-price, not an exclusion); and any **economic reference** (oracle/AMM/price) — is it
manipulable, and does the guard sit on the path the attacker uses or only a sibling path?

## Tooling
Read live state via the chain's own RPC / API / SDK at the pinned point. To execute, use the full rights
you have over the environment (CORE §A): install the chain's SDK/CLI, run a local node / devnet /
simulator at the pinned version, or build a harness importing the chain's own libraries at the matched
build, and replay against real state. Encode the Invariant register as tests over live state; advance
time/height/round to prove multi-step and boundary-gated paths. Only where execution is genuinely
unavailable after you've exercised those rights do you simulate the logic against read live state — and
then label it inference, not execution.
