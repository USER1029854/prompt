# Module — Cosmos SDK app-chain (incl. Cosmos EVM / EVM-precompile chains)

Load with CORE.md. Mechanics for auditing a sovereign SDK chain: the value logic lives in Go modules
(keepers, handlers, `BeginBlock`/`EndBlock`, ante handlers), not in deployed contracts — so "the
deployment" is a **binary at a height**, and the "verified source" is the tagged release whose build
you must match, not assume. Where the chain also runs Cosmos EVM, load EVM.md too; the seam between
the EVM and the bank/SDK state is the highest-yield surface on these chains.

## Atomic unit — read this first, it is the recurring killer
The atomic unit is **not** the transaction. A `Msg` handler can fail while sibling messages in the
same transaction, or prior state writes in the same handler, persist — depending on how the code
manages the `sdk.Context`, cached contexts, and `CacheContext()`/`Write()` commits. Two exact traps:
- **A handler returns an error and the caller logs it and continues**, with state already written to
  the (uncached) context before the failing step. The write survives the failure meant to guard it.
  Enumerate every place a handler's error is logged-and-continued rather than causing a rollback, and
  for each, what state was committed before the error point.
- **Batched messages** in one broadcast: does each message get its own cache-wrapped context that
  only commits on success, or do earlier messages' writes persist when a later one fails or clobbers
  shared state keyed by a common id? A later message overwriting a voter/record the earlier ones
  created, then marking it done, is exactly this seam.
State the atomic unit explicitly for every value-mutating handler: transaction, message, or a
manually cache-wrapped sub-scope — and find the code written as if it were one when it is another.

## Arithmetic semantics (Lens C)
Cosmos SDK value math uses `math.Int` (arbitrary precision, panics on overflow of bounded conversions
like `.Int64()`/`.BigInt()` truncation) and `math.LegacyDec`/`sdk.Dec` (fixed 18-decimal). `Dec`
operations round — `.TruncateInt()` floors, `.RoundInt()` rounds half-up, `.Quo` vs `.QuoTruncate` vs
`.QuoRoundUp` differ — and **choosing the wrong rounding direction on a payout vs a charge favors the
caller**. Find every `Dec` division and truncation on a value path; state its direction and beneficiary.
Watch `Int`↔`Dec` conversions and `.Int64()`/`uint64` downcasts that truncate silently, and any place a
panic mid-handler is recovered (a recovered panic that leaves partial state is a Lens D failure site).

## Cosmos EVM / precompile seam (Substrate ↔ substrate, Lens D)
When an SDK chain embeds the EVM, precompiles bridge EVM execution into native modules (bank, staking,
distribution, ICS20/IBC transfer). The recurring critical: **state written inside a nested EVM call
context is not reflected in — or is double-counted against — the outer context**, letting the same
balance be spent twice in one transaction; or a precompile that performs a partial state write and
then the surrounding EVM frame reverts, leaving the native-side write committed (or vice versa).
Check every precompile that moves value: does it journal/snapshot consistently with the EVM's
own revert semantics, so that an EVM revert unwinds the native write and a native error unwinds the
EVM frame? Vesting-account, staking, and balance-handling precompiles have all been hit. This is a
**shared-framework** bug: pin the exact `cosmos/evm` (or ethermint/evmos lineage) version, pull its
advisory list, and confirm each fix is present in the running binary — a published precompile advisory
unapplied here is the single highest-probability finding.

## Deriving the system
- **Genesis + upgrades.** The live parameter set is genesis + every passed governance param-change +
  every software upgrade handler. Read current params via the chain's REST/gRPC (`/cosmos/...params`,
  module query endpoints) at the pinned height, not from the repo's defaults.
- **Module accounts.** Enumerate every module account and its balance (`x/auth` module accounts:
  reserve, pools, fee collector, bonded/not-bonded pools, distribution). These are the pools value
  leaves from — the Exit register. Reconcile each against the module's internal accounting (the
  bank/supply invariant is your Invariant register's backbone).
- **Custom modules.** The bespoke modules (an AMM, a lending market, a bridge/observation module, a
  trade-account module) are the target. Read their keeper for every `SetX`/`GetX` on the store, every
  `SendCoinsFromModuleToModule`/`Account`, every mint/burn.
- **Invariants the chain itself declares.** `RegisterInvariants` lists what the team believes must
  hold; a registered invariant that is only checked in `crisis` mode (not every block) is a guard
  priced at "never runs" — note it.

## Guard pricing — Cosmos specifics
- **Governance.** On-chain gov can change params, spend the community pool, and run upgrade handlers.
  Price control against live bonded stake and quorum/threshold/veto — and check whether any critical
  param (a cap, a fee, an oracle source, a module address) is gov-settable with no timelock, making
  it a live dormant-path lever.
- **Uncapped subsidy / mint against a small pool.** The recurring economic seam: a slash, subsidy,
  reward, or redemption amount computed as `pool.ValueInX(amount)` **without capping by the pool's
  own live balance**. Read the live pool depth and the live reserve that is supposed to fund the
  payout; if the reserve is a fraction of a plausible draw, the guard is priced at ~0. Check for a
  capped path (`_v96`) beside an uncapped one (`_v92`) — the `SetPool`-before-`Send` ordering means
  the inflated state can persist even when the funding send fails.
- **Observation / voting quorum (bridge & oracle modules).** How many validators/oracles must attest,
  and is the set enumerated from live state? A quorum guard is only as strong as the honest-majority
  assumption and the correctness of the tally — and the tally is often the bug (a voter record keyed
  by a txid that a later message can clobber).
- **Ante-handler guards.** Fee, gas, signature, and replay checks live in the ante handler. A bug
  here (a gas refund without a gas charge, a signature check skippable via a message-type omission)
  affects every transaction.

## The unread Cosmos surface (attention inversion)
- **`BeginBlock`/`EndBlock`** logic: no external caller, no external reviewer, moves value every
  block (reward distribution, slashing, auctions, outbound queue processing). Highest-yield unread
  surface on these chains.
- **The keeper-to-keeper call** across modules — module A's `EndBlock` calls module B's keeper with a
  value B trusts. Cross-module is where Lens A and Lens F live here.
- **`_v92`-style versioned handlers** kept for historical replay/upgrade compatibility, still
  reachable.
- **Migration/upgrade handlers** (`x/upgrade`) that rewrite store layout — a store-key migration that
  misreads the old encoding is a lifecycle seam.
- **IBC**: the packet-receipt / timeout / acknowledgement paths, and whether a `recvPacket` credits
  before verifying, or a timeout refunds a packet that was also relayed.

## Tooling
Query live state via the chain's REST/gRPC/`abci_query` at the pinned height. Reconstruct sets from
events (`tendermint`/`cometbft` tx search, block results). To execute: sync or snapshot a node at the
pinned height and replay against it, or build a Go test harness importing the modules at the tagged
version (match the running binary's build — `go build` flags, sdk version, ledger tags — before
trusting it as the deployment). Encode invariants as Go tests over keeper state; advance height in
the harness to prove multi-block and `EndBlock`-gated paths. Where you cannot run a node, simulate the
handler logic against read live state and label it as inference, not execution.
