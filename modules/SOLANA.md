# Module — Solana / SVM

Load with CORE.md. On Solana the program is stateless code; all state lives in **accounts** the caller
passes in. This inverts where the bugs are: the classic EVM question "does this function check the
caller" becomes "does this program check that the accounts it was handed are the accounts it thinks
they are." Almost every Solana exploit is a seam between *the account a program assumed* and *the
account an attacker actually passed*.

## Atomic unit
The **transaction** is atomic across its instructions — but a transaction can contain many
instructions, including instructions to *other* programs, and CPI (cross-program invocation) runs
nested. The Lens D traps: an instruction that assumes a prior instruction in the same transaction ran
(it may not have, or a different one did); CPI where the callee is attacker-chosen because the program
id wasn't checked; and `invoke_signed` PDA authority leaking because the seeds are guessable or
unchecked. Instruction introspection (the `Instructions` sysvar) is trusted by some programs to know
"what else is in this transaction" — that is attacker-arrangeable.

## The account-validation seams — the core of every Solana audit
For **every account** an instruction reads or writes, the program must establish four things. A miss
on any one is a seam:
- **Owner.** Is the account owned by the program that's supposed to own it? An account whose `data`
  the program deserializes and trusts must be owned by this program (or the expected program).
  Missing owner check → an attacker passes a look-alike account they populated. This is the single
  most common Solana root cause.
- **Signer.** Is the account that must have authorized this actually a `is_signer`? Missing signer
  check → anyone acts as anyone. (Wormhole's $325M was a signature/validation failure of this family.)
- **Identity / address.** Is this the *specific* account expected — the right PDA, the right mint, the
  right config, the canonical account — not merely *an* account of the right shape? Check PDA
  derivation: correct seeds, correct program id, and canonical bump (`find_program_address`, not an
  attacker-supplied bump). A program that accepts any account matching a discriminator, without
  binding it to the expected address, is exploitable.
- **Type / discriminator.** Anchor's 8-byte discriminator distinguishes account types; a native
  program that doesn't tag and check type can be handed one account type where another is expected
  (type confusion). Also check for account substitution between two accounts of the *same* type
  (e.g. passing the vault's token account where the user's is expected). Event-discriminator checks on
  cross-program deposit/relayer callbacks belong here too — a missing one lets a forged event be
  processed as genuine.
- **Aliasing / distinctness.** Where an instruction takes two account params that must be *different*
  (a send account and a receive account, source and destination, a pool and its counterparty), does it
  enforce `key_a != key_b`? Passing the *same* account for both — so a second serialize overwrites the
  first and state desyncs from the real vault balance — is a recurring Solana drain (`require_keys_neq`
  absent). Enumerate every pair of accounts the logic assumes distinct.

Enumerate every account of every instruction and tabulate which of the five checks it has (owner,
signer, identity/PDA, type, distinctness). The gaps are your Q1/Lens E findings before you've thought
about economics at all.

## Deriving the program & state
- The program is a deployed BPF/SBF binary at a program id; if unverified source, the target is the
  binary — dump it (`solana program dump`), and use the IDL if published (Anchor `idl`) but treat the
  IDL as a claim, not the code.
- **Upgrade authority.** Read the program's `ProgramData` upgrade authority — a live upgrade authority
  is an authority-over-the-target seam (can replace the code over live funds). Note whether it's a
  multisig, a DAO, or a single key, and price it.
- **PDAs and state accounts.** Enumerate the config/global/state PDAs and the vault token accounts
  (the value pools → Exit register). Reconstruct sets (all markets, all vaults) from creation
  transactions / program logs, not from a getter.
- **Token accounts.** SPL-Token vs Token-2022. Token-2022 extensions are a semantics seam: transfer
  hooks (arbitrary code on transfer — the Solana analog of ERC777), transfer fees (amount received ≠
  amount sent — the fee-on-transfer analog), non-transferable, permanent-delegate (a third party can
  move the balance), confidential transfers. For every value path, establish which token program and
  which extensions, and where the code breaks if the mint has one it didn't expect.

## Guard pricing — Solana specifics
- **Authority checks.** An `authority` field the program compares against — is it compared to a
  hardcoded/config value that is correct, or to an account the attacker also supplies? A guard that
  checks `ctx.accounts.authority.key == some_account.authority` where `some_account` is
  attacker-passed is priced at 0.
- **Oracle / price.** Pyth/Switchboard: check staleness (`publish_time` vs slot), confidence
  interval, and status. A program reading a price account without checking it's the *expected* oracle
  account (identity seam) or without staleness bounds is the Solana oracle seam.
- **Math.** Solana programs are Rust: overflow behavior depends on build profile — release builds
  wrap by default unless `overflow-checks=true`. Confirm the deployed binary's overflow behavior;
  unchecked `as` casts truncate; `checked_*` vs raw ops. This is a real guard-existence question, not
  a formality, because the default is unsafe.
- **Rent / lamports.** Draining lamports from an account to below rent-exemption, closing accounts and
  re-initializing (a "reinit" attack where a closed account is re-passed and re-used), and the
  `close` pattern that doesn't zero data or reassign owner.

## Proof / verifier seams (Lens B)
Where a program verifies a Merkle proof, a ZK proof, or a signed message (ed25519/secp via the
instructions sysvar or a precompile): confirm the message/inputs the program acts on are covered by what
was verified, the verifying key/root is the expected account (identity seam — not an attacker-passed
account), and a valid proof over attacker-chosen public inputs is rejected. Signature verification via
the instructions sysvar is a classic seam — confirm the program checks the sysvar instruction is the
expected ed25519-program instruction over the expected message, not merely that *some* signature
instruction exists.

## The unread Solana surface (attention inversion)
- Native (non-Anchor) programs, where the checks are hand-rolled and easy to omit — Anchor gives
  owner/signer/discriminator checks by default, native code doesn't.
- **Deprecated-but-live programs.** A program the UI stopped calling is still callable at its program id;
  an old AMM/lending version with a missing account check is a standing drain (real 2026 case: a
  deprecated AMM's remove-liquidity path accepted a forged LP-mint account). Enumerate old versions.
- CPI targets where the invoked program id isn't pinned, and third-party SDK callbacks (e.g.
  ephemeral-rollup undelegation) that don't re-verify PDA seed derivation.
- The `close`/`realloc`/reinit paths (lifecycle seam).
- Any instruction that trusts the `Instructions` sysvar or a prior instruction — and **durable nonces**,
  which let an attacker hold a validly-signed transaction indefinitely and land it later (a facilitation
  vector for pre-signed admin/migration actions).
- Admin/config instructions dismissed as privileged — price the upgrade authority and the admin key.

## Tooling
`solana`/`anchor` CLI for live account reads at a pinned slot; `solana account`/`getAccountInfo` for
state; program logs and `getSignaturesForAddress` for set reconstruction. Execute against a local
validator forked from mainnet state (`solana-test-validator --url mainnet --clone <accounts>`), or
`bankrun`/`litesvm` for fast harnesses, or Anchor's `--fork`. Encode invariants as tests that build
malicious `AccountInfo` sets (wrong owner, wrong PDA, wrong signer, substituted account) and assert
they're rejected — the malicious account set *is* the fuzz input on Solana. Advance slots to prove
staleness and multi-instruction paths.
