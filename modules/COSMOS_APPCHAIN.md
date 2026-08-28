# Module — Cosmos SDK app-chain (incl. Cosmos EVM / EVM-precompile chains)

Load with CORE.md. Mechanics for auditing a sovereign SDK chain: the value logic lives in Go modules
(keepers, handlers, `BeginBlock`/`EndBlock`, ante handlers), not in deployed contracts — so "the
deployment" is a **binary at a height**, and the "verified source" is the tagged release whose build
you must match, not assume — and the version the node reports *now* may be newer than your pinned height,
an upgrade or hotfix applied since, so bind to what was live **at** that height (from the block's own
version and the upgrade history), not what runs today; auditing a later build reviews code the pinned
deployment never ran. Where the chain also runs Cosmos EVM, load EVM.md too; the seam between
the EVM and the bank/SDK state is a prime surface on these chains — value-moving logic crosses two
state machines there, and each side is reviewed as if the other guaranteed consistency.

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
advisory list, and confirm each fix is present in the running binary.

Two named forms this took, both worth checking explicitly:
- **Mirrored-balance desync / underflow.** The EVM keeps a *mirror* of the native bank balance; a
  precompile that writes the post-operation balance back can underflow it. The shape to check: an account
  made into a vesting account (e.g. by precomputing the contract's deploy address, converting that
  address to a vesting account, then deploying so the contract inherits vesting status) delegates one wei
  more than its spendable balance, and the staking precompile writes the mirror to ~2²⁵⁶. Total supply never
  changes, so a supply invariant won't catch it. Check every precompile that mirrors a balance for
  under/overflow and for vesting/locked-balance edge cases.
- **Caller → cosmos-account authorization mapping.** EVM `msg.sender` semantics do **not** carry
  through to a native-module call. When a contract calls a native module (staking, bank, vesting), which
  cosmos account is the authenticated source, and can the caller name *any* account as the fund source?
  A binding that requires the funder to authorize, evaluated against the wrong account, lets a contract
  move anyone's funds. Trace, at every precompile/module boundary, exactly whose authority is checked.

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
- **The signing / consensus / bridge-vault layer.** For a chain that runs its own outbound signing,
  threshold signatures (TSS/MPC), or cross-shard/receipt consensus, that layer is **in scope** — it is
  where several 2026 L1 losses lived (a TSS fork years behind upstream that skipped the zero-knowledge
  proofs validating key formation, letting a bonded-in node reconstruct the vault key over successive
  signing rounds; cross-shard receipts not bound to the authenticated source header, replayed to mint).
  This is simultaneously an authorization-acquirable case (bond/stake to join the validator/signer set —
  price that, §4), a Q3 case (a skipped or mis-specified soundness check in the signing protocol), and a
  fleet case (the crypto library is a fork behind upstream). Read the TSS/keygen library at its pinned
  version against upstream, and confirm the receipt/nullifier binds to authenticated source data.

## Tooling
Query live state via the chain's REST/gRPC/`abci_query` at the pinned height. Reconstruct sets from
events (`tendermint`/`cometbft` tx search, block results). To execute: sync or snapshot a node at the
pinned height and replay against it, or build a Go test harness importing the modules at the tagged
version (match the running binary's build — `go build` flags, sdk version, ledger tags — before
trusting it as the deployment). Encode invariants as Go tests over keeper state; advance height in
the harness to prove multi-block and `EndBlock`-gated paths. Where you cannot run a node, simulate the
handler logic against read live state and label it as inference, not execution.
