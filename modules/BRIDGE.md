# Module — Cross-chain bridge / messaging

Load with CORE.md, plus the substrate module for **each** side (EVM.md, COSMOS_APPCHAIN.md,
SOLANA.md, and the non-EVM/exotic side even if that's the one you can't read easily — *especially*
that one). A bridge is nothing but seams: it exists to restate a fact from chain A as a fact on chain
B. The audit is the interrogation of that restatement.

## The one rule that catches most bridge hacks
**Audit the side you can't read.** The recurring bridge failure is that reviewers audit the side
written in the language they know (usually the EVM/Solidity side) and wave through the other side —
the Cosmos module, the Solana program, the non-EVM chain's custody logic, the off-chain relayer/
attester. The unread side is where the money left in incident after incident. If one side is in a
substrate you can't easily analyze, that is not a reason to scope it out — it is the reason to spend
your budget there. State explicitly, in the verdict, if your result does not cover a side; a clean
verdict that silently excludes the exploited side is worse than no verdict.

## The three questions of every bridge
Every bridge credits value on B because it believes something happened on A. Three seams, always:

### 1. Does the message correspond to a real, final event on the source? (Claim ↔ settlement)
- **What is actually verified?** A light client / consensus proof, a committee/validator multisig, an
  external attester (e.g. a CCTP-style attestation), or an optimistic window. Identify it exactly.
- **Is the *event* real, or just the *message* valid?** The purest bridge exploit: the attacker gets
  a genuinely-valid attestation over a message describing a deposit **that never economically
  happened** — e.g. calling the source messenger's `sendMessage` directly to emit a well-formed
  message with no actual burn/lock behind it. The signature verifies; nothing was locked. The
  destination must tie the credit to a real value movement on the source (a real burn, a real lock,
  a real balance increase), not merely to a well-formed signed message. Find the line on the
  destination that checks the source *event* — its absence is the finding.
- **Sender/recipient binding.** Does the destination check that the message's declared source sender
  is the *canonical* source-side bridge/messenger contract, and the recipient is the expected local
  handler — not attacker-chosen addresses in `hookData`? Missing sender/recipient checks let a forged
  message be processed as genuine.
- **Amount binding.** Is the credited amount derived from the *verified* portion of the message, or
  from an attacker-supplied field (`hookData`, a memo, an unsigned tail) trusted alongside the proof?

- **Proof-system verifier (ZK / light client / MMR).** If verification is a proof rather than a
  signature set: is every public input the destination acts on *constrained by* the proof (an
  unconstrained recipient/amount/nonce under a valid proof is attacker-controlled)? Is the verifying key
  / trusted root the expected one and not attacker-settable? Is a valid proof over attacker-chosen inputs
  still rejected? A verifier misconfiguration credits value against a perfectly valid proof.

### 2. Can the message be replayed, reordered, or collided? (Name ↔ name, Authority ↔ action)
- **Replay.** Is there a consumed-nonce / used-hash set, and is it keyed correctly (per source chain,
  per destination, per message) and actually checked *before* the credit? Can the same proof be
  submitted on two destination deployments (byte-identical contracts on two chains sharing a domain
  separator)? Can a message valid for domain X be replayed on domain Y?
- **Ordering / dependency.** Does crediting assume messages arrive in order, or that a paired message
  (mint then unlock) both arrive? Can one be delivered and the other timed out / refunded — crediting
  twice?
- **Identifier collision / poisoning.** The denom/asset-registry seam: does a permissionless
  registration bind a source asset id to a destination custody address or wrapper, and can an
  attacker register a fabricated id that collides with, or aliases, a real asset — mapping "worthless
  token X" to "real USDC custody"? Enumerate who can write the id↔asset mapping and whether collisions
  are rejected. Check hash/encoding ambiguity: concatenated variable-length fields (chain id + sender
  + payload) that can be re-split to the same hash — a real 2026 drain reinterpreted a 3,097-unit
  authorization as 203,000,000 because 14 variable-length fields were concatenated without delimiters.
- **Parser disagreement across components (Q3).** Where two components deserialize the *same* bytes — a
  UTXO layer and an EVM relay reading one transaction, a source chain and a destination reading one
  message — confirm they agree on the interpretation. A payload one side reads as asset X and the other
  as native gas, or two asset commitments on one output index, mints value one side never debited.
- **Receipt / marker binding (Q3).** A spent-receipt or nullifier marker must be derived from the
  *authenticated* source header (shard id, block number, source chain), not from replayable fields.
  Unbound cross-shard receipts were replayed to mint at L1-consensus scale.

### 3. Is the accounting conserved across the two sides? (Claim ↔ settlement, solvency)
- **Mint ⇔ lock invariant.** Total wrapped/minted on all destinations must equal total locked in
  custody on the source. Reconcile live: read the source custody balance and the destination
  mint supply at the pinned point on *each* chain. A gap is stranded value, phantom value, or a live
  hole. This is the bridge's master invariant — encode it.
- **Amount equivalence — the check that lives in neither chain.** The value *committed on the source*
  must equal the value *paid on the destination*. This check often exists on neither side by default: a
  real 2026 drain paid out ~$11.6M against a structurally-valid import blob committing ~$0.01, because
  the destination verified the proof's *form* but never that source-committed amount == destination
  payout. For every inbound settlement, find the line comparing the two amounts; its absence is the
  finding even though every signature and proof verifies.
- **Credited-before-verified windows.** Does `receive`/`recv` credit or forward before the proof is
  fully checked, or trust an internal credit record that a forged message wrote? The Allbridge-shaped
  seam: the router trusted an internal credit and paid out; a flash loan topped the balance to match
  the forged amount so the transfer succeeded. Check whether a just-arrived genuine deposit's funds
  can be swept by a separately-forged credit against the same pool.
- **Fee-on-transfer / rebasing / decimals across chains.** "Amount sent" on A ≠ "amount received" on
  B if a token behaves non-standardly on either side, or if decimals differ across the two chains'
  representations of "the same" asset.

## Guard pricing — bridge specifics
- **Committee/multisig.** Price control of the signer set: how many keys, how held, and — the acquire
  question — is the set enumerated from live on-chain state, or is a stale/misconfigured set live?
- **Attester trust.** An external attester (Circle CCTP, an oracle network) is a guard whose price is
  0 against forged-message attacks if the destination trusts the attestation *without* checking the
  underlying event. The attester is honestly attesting to a message the attacker authored; the guard
  never fails, it just guards the wrong thing.
- **Optimistic window.** Price the challenge: is anyone actually watching and able to challenge within
  the window, and what does challenging cost vs. the fraud's payoff?

## The atomic-unit seam across substrates (Lens D)
A and B have *different* atomicity, finality, and reorg models. A "finalized" deposit on a fast/
reorg-prone source that B credits before source finality is a double-spend seam: reorg the source,
keep the destination credit. State each side's finality assumption and whether the bridge's
confirmation depth respects it. Two chains' block times, reorg depths, and "finality" meanings are a
Substrate ↔ substrate seam by construction.

## The unread bridge surface (attention inversion)
- The non-EVM / exotic-chain custody side (audited least — this is where you spend budget).
- The off-chain relayer/attester/indexer: what decides "a deposit happened," and what breaks if it's
  wrong or compromised. Name it, state the decision it controls, gather on-chain evidence of how it
  actually behaves.
- Emergency pause/unpause and admin withdraw on custody.
- The refund/timeout path (pairs with a delivered packet for double-credit).
- Version drift: the same bridge deployed on 6 chains where one runs an older, unfixed handler.

## Tooling
Fork/replay **each** side at a pinned point on that chain; the master reconciliation (mint supply vs.
locked custody) is read live on every chain and drift-checked at head. Reconstruct the message set and
the id↔asset mapping from events on both sides. Encode the mint⇔lock invariant and the
credit-requires-real-source-event property as executable checks; build a forged-message harness (a
well-formed, validly-attested message with no backing event) and assert the destination rejects it —
if it doesn't, that is the PoC.
