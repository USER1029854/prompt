# Module — EVM

Load with CORE.md. This carries EVM-specific mechanics for the core's method. It does not repeat the
method. Where the core says "price the guard," "state the atomic unit," "enumerate the set" — here is
how, on the EVM.

## Atomic unit
The **transaction**. A revert unwinds all state in the transaction; that is the assumption reviewers
correctly hold on the EVM and wrongly carry to other substrates. The EVM traps for Lens D are
elsewhere: `call`/`delegatecall`/`staticcall` return a success boolean that is *silently ignored* if
unchecked (a failed `.call` does **not** revert the caller); `try/catch` swallows a revert and lets
execution continue; low-level calls to an address with no code return `success=true`; and a
sub-call's revert is only fatal if the caller bubbles it. Enumerate every low-level call site and
every try/catch; for each, what state was written before it and does the code proceed on failure.

## Arithmetic semantics (Lens C)
Solidity `>=0.8` reverts on overflow/underflow for checked ops — but **`unchecked { }` blocks opt out**,
and **casts / narrowing conversions truncate silently** (`uint256`->`uint128`, `int`->`uint`), as do
explicit shifts. `<0.8` and inline assembly wrap by default. Find every `unchecked` block, every cast on
a value path, and every assembly arithmetic op; these are where a checked-by-default reviewer stops
looking. Division is floor; **round direction is a first-class question** — for every `mulDiv`/`/`/
fixed-point op on an exit path, state whether it rounds toward the protocol or the caller and who keeps
the remainder. A single floor-division dropping a rate adjustment, repeated across dozens of micro-swaps
in one transaction, was a nine-figure loss.

## Deferred / transient settlement (Lens C)
Systems that permit a transient invariant violation as long as the transaction "nets out" — Uniswap V4
`unlock`/flash-accounting, Balancer vault internal balances and `batchSwap`, EIP-1153 transient storage,
any flash-loan-and-settle-at-end pattern — let an attacker act on state *while the books are transiently
unbalanced*. Identify every such mechanism; ask what an outsider can do inside the unsettled window
(price off a pool mid-batch, mint/redeem against a transiently-wrong balance) before the net-settle.

## Proof / verifier seams (Lens B + Lens G)
Where a contract verifies a Merkle proof, a ZK proof, or an external attestation: confirm every public
input the contract acts on is *constrained by* the proof (an unconstrained public input under a valid
proof is attacker-controlled); confirm the verifying key / merkle root / trusted signer is the expected
one and not settable to an attacker's; confirm a valid proof over attacker-chosen inputs is still
rejected. A verifier misconfiguration authorizes withdrawals against a perfectly valid proof.
The check-that-doesn't-hold (Lens G) forms recur on the EVM specifically as:
- **ERC-1271 `isValidSignature` whose static-call success is unchecked** — a failed verify returns a
  falsy/empty result the caller reads as valid, bypassing a smart-account/module auth gate.
- **Scope mismatch** — a proof or signature covers N entries while the settlement/consumer loop
  processes an attacker-controlled M ≤ N (verify what the proof commits to equals what the code
  traverses).
- **Counts a proxy for identity** — a guard that checks a count/length where it must check identity or
  uniqueness (a bond ledger keyed by count, a "seen" set never actually queried before the credit).

## Deriving contracts from the target
- Runtime code + verified source: the chain's own explorer verification for that exact address, full
  source tree, not the flattened single-file view. Unverified → decompile (heimdall, Dedaub,
  panoramix), extract constants, simulate.
- Proxies: resolve to the implementation that *runs*. EIP-1967 impl slot
  `0x360894...bbc` and admin slot `0xb531...103`; EIP-1822 `proxiableUUID`; beacon proxies;
  diamonds (EIP-2535) — enumerate facets via `facets()` / `DiamondCut` events, each facet is a
  component with its own selectors. A proxy read as its implementation's source but pointing at a
  different implementation is a classic miss.
- Factories: children live in `PoolCreated`/`PairCreated`/`MarketListed`/`VaultDeployed`/clone-deploy
  events, or the enumerable array (`allPairsLength()`+`allPairs(i)`). Reconstruct **all** members,
  then rank by balance. CREATE2 children: compute the address set from the salt scheme if the events
  are incomplete.
- Upward graph from logs: `RoleGranted`/`RoleRevoked` (AccessControl), `OwnershipTransferred`,
  `Upgraded`, `Approval` on every token the system holds, and any bespoke `*Set`/`*Registered` event.

## Guard pricing — EVM specifics
- **Governance.** Read the *live* `totalSupply()` of the voting/wrapped-voting token and the live
  quorum/threshold/`proposalThreshold`. Wrapped voting tokens (Aragon OSx TokenVoting, Governor +
  ERC20Votes, Zodiac) frequently have a float far below the underlying — price control against the
  *wrapper's* supply, not the underlying asset's. Check delegation: is voting power snapshotted, and
  can it be flash-acquired within a block if not `getPastVotes`-gated?
- **Timelock / delay.** Zodiac Delay, OZ TimelockController, Governor timelock. The price is
  reconfigurability: can the delayed party (a module, a role) call back into the delay to set cooldown
  to 0, or enable itself as an exempt module? Trace `owner()`/`admin` of the delay and every address
  that can call its setters — this is the exact Term-shaped seam, and it is a Lens C + Lens F
  (lifecycle) interaction.
- **Economic / oracle.** Distinguish `slot0()` spot from a TWAP (`observe()`), and — the key check —
  **map which user-facing path reads which.** Grep every read of the price/reserve source and list
  the call sites; a deviation guard on `rebalance()` but not `mint()`/`burn()` is the Arrakis-shaped
  seam. Chainlink: check `updatedAt` staleness, `answeredInRound`, min/max circuit-breaker bounds,
  and L2 sequencer-uptime feed. Any `getReserves()`/`balanceOf(pool)` used for pricing is
  flash-manipulable unless time-averaged.
- **Cryptographic.** ECDSA `ecrecover` returns `address(0)` on malformed input — if a trusted-signer
  slot can be zero, malformed sigs authorize. Check EIP-712 domain separator binds `chainid`,
  `verifyingContract`, and a version; check the signed struct covers every field the code acts on
  (an unsigned `amount` or `to` alongside a valid signature is attacker-controlled); check nonce /
  used-hash replay protection and that it isn't shared across byte-identical siblings on other
  chains. `permit` front-run / silent-no-op on non-conforming tokens.
- **Reentrancy guard.** Presence of `nonReentrant` on the mutating path says nothing about
  *read-only* reentrancy — a view read by an external protocol during your callback window. Also
  check cross-function reentrancy (guard on `withdraw` but not the `getReward` that shares the
  accumulator) and ERC777/ERC721/hook-bearing tokens that hand execution to the counterparty
  mid-transfer.

## Set enumeration
Never trust a getter that returns "the" address; enumerate history. Roles: replay `RoleGranted` minus
`RoleRevoked`. Approvals the system granted: `Approval` logs where owner is a system contract.
Factory children: creation events. Reconstruction goes on disk; the claim is `UNVERIFIED` until it
does.

## Storage / layout (Lens D + lifecycle)
Read raw slots and reconcile against declared layout, mandatory for upgradeable/assembly/diamond/
library-fixed-slot contracts. Across an upgrade, diff layout: a variable inserted, reordered, or
resized makes live storage mean something the new code doesn't expect. Check ERC-7201 namespaced
roots, EIP-1967 slots, and any constant-hashed slot from your constant extraction. An initializer
callable on the implementation directly, or an `_initialized` slot a migration left at zero, is a
lifecycle seam. **Slot collision** is a live drain, not just an upgrade hazard: a `mapping`/variable
whose slot coincides with a library's fixed sentinel slot (e.g. a reentrancy guard writing a huge
locked-constant that is then read back as a user's reward/balance) turns the guard itself into the
exploit. For every fixed-slot library the contract inherits, compute its slot and confirm nothing in
the contract's own layout lands on it.

## The unread EVM surface (attention inversion)
- `_v1`/`_v2` sibling functions where one caps or checks and the other doesn't.
- The implementation behind a proxy nobody re-verified after the last upgrade.
- Callbacks: flash-loan (`uniswapV2Call`, `onFlashLoan`, `receiveFlashLoan`), `onERC721Received`,
  ERC777 hooks, swap/lock callbacks, AA `validateUserOp`. Each is an entry point an outsider triggers
  and the dispatcher often omits.
- The library shared across contracts, diffed against real upstream and against its **advisory list**
  at the pinned version (OZ SECURITY advisories, Solady, the specific commit).
- The `receive()`/`fallback()` and any `sweep`/`skim`/`sync`/`recoverERC20` recovery function.

## Tooling
`cast`/`foundry` for live reads and forking (`forge test --fork-url … --fork-block-number N`);
`cast storage`, `cast call`, `cast logs` for state and set reconstruction; heimdall/Dedaub for
decompilation; `slither`/`mythril` for candidate generation (compile with the deployment's exact
solc + optimizer + evm-version from metadata, timeboxed — a failed build costs only the analyzer
pass). Encode invariants as Foundry invariant/fuzz tests against the fork; warp with `vm.warp` /
`vm.roll` to prove delay-gated and multi-block paths.

## Chain semantics per deployment
`block.number` on L2s may track L1 or the L2; `block.timestamp` source and manipulability;
sequencer-uptime feed existence and whether the code consults it; reorg depth / finality; mempool
visibility (matters for whether an ordering-flavored bug is truly ordering or a real defect that
survives a private mempool); PUSH0 / target-EVM-version support; gas-token differences where the gas
token isn't ETH; precompile availability. Identical bytecode on two chains is two deployments —
verify implementation, config, and roles on each; the weakest governs.
