# Module — Move (Sui / Aptos)

Load with CORE.md. Move's arithmetic and object semantics differ enough from the EVM that a reviewer
trained on Solidity misses whole classes — most sharply, Move aborts on arithmetic overflow but a
bit-shift truncates silently, so a wrong threshold on a shift/cast passes every overflow check and still
drops value. Mechanics only here; the method is in CORE.md.

## Arithmetic semantics — read this first (Lens C)
- **Move aborts on `+ - *` overflow and on divide-by-zero** — so those are safe *by default*, which
  lulls reviewers. **But bit-shifts (`<<`, `>>`) truncate silently**, and `as` casts between integer
  widths truncate silently. Any value that reaches a shift or a downcast must be bounds-checked by hand,
  and the check's threshold is the bug surface: a threshold that permits an oversized value to pass and
  then lose significant bits in the shift is exactly the mint-huge-liquidity-for-one-token defect. Find
  every `<<`, `>>`, and `as`; for each, the hand-rolled bound that protects it; evaluate that bound at
  its boundary, not in the middle.
- Fixed-point/`u128`/`u256` math libraries (`math_u128`, `full_math`, CLMM tick/sqrt-price math) are the
  crown-jewel value math. Round-direction and intermediate-truncation live here; fuzz them at edges in
  §6.
- No implicit reentrancy in the EVM sense (no dynamic dispatch to arbitrary code mid-call), which
  removes one bug class but *shifts weight onto the arithmetic and the object/capability model* — spend
  the freed attention there.

## Object & capability model (Lens B/C/E)
- **Everything is an object** with an id, owned or shared. Value lives in objects (`Coin<T>`, pool
  objects, position/LP objects). Authority travels as **capability objects** (an `AdminCap`,
  `TreasuryCap`, a witness type): holding the object *is* the permission. The seams: is a capability
  object ever transferable to, or mintable by, an outsider? Is a shared object mutated without checking
  the caller holds the matching capability? Can a `TreasuryCap<T>` (mint authority) be reached?
- **`public` vs `entry` vs `public(friend)`** functions and the **module init**: enumerate every
  `public`/`entry` function an outsider can call, and every capability it requires. A value-moving
  `public` function whose only guard is an argument the caller supplies (a pool object, an authority
  object they also pass) is unguarded.
- **Type confusion / witness abuse.** Generic functions parameterized by a type `T` — can an attacker
  instantiate `T` with a type that satisfies the constraints but breaks an assumption (a fake coin type,
  a one-time-witness reused)? Confirm the "one-time witness" pattern is actually one-time.
- **Object ownership transfer / `public_transfer`.** Can a value or capability object be transferred out
  of the protocol's control, or a wrapped object unwrapped by someone who shouldn't?

## Deriving the system
- The published package(s) at their address. Source binds only by a reproducible-build match against the
  on-chain module bytecode (Sui/Aptos source verification); confirm it before trusting source. Absent it,
  the target is the compiled bytecode module — disassemble it. Read the on-chain package, not a repo.
- **Upgrade policy.** A package's `UpgradeCap` and its policy (immutable / compatible / additive) is the
  authority-over-target seam: a live compatible-upgrade cap can replace value logic over live funds.
  Price who holds it.
- Enumerate shared objects (pools, registries, vaults) and their live balances (the Exit register).
  Reconstruct sets (all pools, all markets) from creation events / the registry object's contents, not
  from a getter.
- Coin standards and their extensions (Sui `Coin`/regulated coins with deny lists; Aptos fungible-asset
  store) are the token-semantics seam: deny-list/freeze, fee-on-transfer analogs, and decimals across a
  math path.

## Guard pricing — Move specifics
- **Capability = the guard.** Its price is the cost of obtaining the capability object, or of reaching a
  function that acts as if the caller held it. A `public` fn that skips the capability check is priced
  at 0.
- **Shared-object contention / equivocation** is a liveness/ordering concern, usually out of scope, but
  a shared object whose consistency the code assumes across a PTB can be a real seam.
- **Arithmetic guard** (the bounds check before a shift/cast): price it by finding an input at the
  boundary that passes the check yet corrupts the downstream value. This is the wrong-threshold-on-a-shift shape; test it in
  §6, don't eyeball it.

## The unread Move surface (attention inversion)
- The shared math-helper library every pool imports — trusted as boilerplate, audited by no one who
  treats it as the value path. A wrong bound in a shared `sqrt`/tick/fixed-point helper is a wrong bound
  in every pool at once.
- `public` functions without an `entry`-level review because they're "internal-ish".
- **Deprecated packages and peripheral shared objects still live.** A reward "spool" nobody had called
  in 17 months paid out a trillion-fold inflated points and drained its pool; the object model kept the
  blast radius to that peripheral object, but the object stayed callable. Enumerate deprecated packages
  and the shared objects they still own. Reward/points-index inflation is the shape to watch.
- Upgrade/migration functions and the package `init`.
- Flash-loan / hot-potato patterns: a `Receipt`/hot-potato struct with no `drop`/`store` that must be
  consumed by transaction end — does every path that creates it enforce the repayment invariant, and can
  the intermediate state be acted on (deferred-settlement analog, Lens C)?
- **VM / verifier level.** Move's linear-resource type safety — the guarantee app auditors lean on
  (resources can't be forged or duplicated) — has itself been broken at the VM level (a stale
  module-cache → type-confusion primitive). For a chain running a modified or older Move VM, the VM and
  bytecode-verifier assumptions are in scope, not just the app code.

## Tooling
`sui client`/`aptos` CLI for live object reads at a pinned checkpoint/version; object queries and events
for set reconstruction. Execute against a localnet forked/seeded from mainnet objects, or the Move unit-
test / prover framework: encode invariants as Move tests over real object state, and use the **Move
Prover** where you can to prove arithmetic bounds rather than sample them (this is the strongest possible
form of the Lens C check — a proof that a shift can't truncate beats any fuzz campaign). Fuzz the CLMM/
fixed-point math at edges. Advance checkpoints/version to prove multi-step paths.
