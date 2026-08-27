# How to run the eval — blind, end to end

The point of the eval is to answer one question honestly: **would the audit prompt have caught this
class of bug on a target it had never been told about?** That only means something if the auditor is
*blind* — it must not know which incident it's looking at, or it can recall the answer instead of
deriving it. This runbook is the procedure that keeps it blind and turns a run into a score.

## The two actors — never let them touch
- **The AUDITOR** is a fresh LLM agent (a new Claude Code session, or an API agent loop) running the
  prompt. It may see **only** `PROMPT_BUNDLE.md` (CORE.md + the case's module(s) + the blinded brief) and
  a fork endpoint. It must **not** see: the case JSON, `ANALYSIS.md`, the incident name/date, or a web
  search of the incident.
- **The GRADER** is `grade.py`, run by you afterwards. It sees the case JSON *with* the answer. It never
  runs in the auditor's context.
Keep them on separate sessions (ideally separate machines). Mixing them is the only way to fool yourself.

## Why blind, and why it's imperfect
The model has read about the famous hacks in training. Three things keep the result meaningful anyway,
and you must not skip them:
1. **Score the PATH, not the answer.** Each case lists `must_reach` — the intermediate *observations*
   that constitute having actually walked the path (a live number read, two call-sites listed, a field
   noted as unsigned). The grader scores those, not whether the transcript names the bug.
2. **Flag retrieval.** The grader's `DERIVED` flag catches a run that names the incident *before* making
   any on-chain observation — recall wearing a finding's clothes.
3. **Run clean controls and count false positives.** A prompt that "finds" a critical on a safe target
   is worse than one that misses; recall means nothing without the FP number beside it.
Note the residual leak you cannot fully remove: a contract **address** or a **block number** can be
googled, so a determined model can de-blind itself. This is exactly why the score is the *path*, not the
answer — an auditor that recalls the name but doesn't make the observations still fails.

## Step 1 — build the blinded target (the manual, case-specific part)
The harness cannot do this for you: it needs a real fork/replay pinned **one unit before** the exploit.
- **EVM:** find the exploit transaction on an explorer, take its **block number − 1**, and fork there
  (`anvil --fork-url <archive-rpc> --fork-block-number <N-1>`, or your framework's equivalent). The
  auditor gets the fork RPC URL and the target address(es) — nothing else.
- **App-chain / non-EVM:** the pre-exploit **height** plus the **release binary version** running then;
  replay against a node synced/snapshotted at that height. (For Solana/Move: the pre-exploit slot/version
  and the program id.)
- Hand over the address/id, not the name. Do not include the project, the date, or the loss figure.

## Step 2 — assemble the bundle and prove it's blind
```
./run_case.sh cases/case-02-governance-capture.json runs/case-02
```
This writes `runs/case-02/BRIEF.json` and `runs/case-02/PROMPT_BUNDLE.md`, then leak-checks the bundle.
**The `LEAK CHECK` line must read PASS** (or WARN with only obviously-generic words — read them). If it
says FAILED, the bundle names the incident; fix the case's `blinded_brief` (or the CORE/module text) and
re-run. Never hand a FAILED bundle to the auditor.

## Step 3 — run the auditor blind
In a **fresh** context with no incident knowledge:
- give it `runs/case-02/PROMPT_BUNDLE.md` and the fork endpoint from Step 1;
- instruct it to run the prompt to a verdict and write its **complete** output (plus `manifest.json` if
  it produces one) to `runs/case-02/transcript.txt`;
- do not answer questions about what the target "is", do not let it web-search the incident.
Nothing about the target's identity should enter that session.

## Step 4 — grade
```
python3 grade.py --case cases/case-02-governance-capture.json --run runs/case-02
```
Read three things:
- **PATH** = fraction of `must_reach` observations the transcript actually made.
- **DERIVED** = did it get there from the target, or name the incident before any evidence (retrieval)?
- **PROVEN** = did it produce a fork PoC / executable check, or only reason?
A case counts as **"could have prevented"** only when **PATH ≥ 0.8 AND DERIVED AND PROVEN.** Naming the
bug without the path is a fail, however impressive it reads.

The grader matches `must_reach` by keyword, which is a **proxy**. For any case you're about to trust,
spot-read the transcript to confirm each matched observation is genuinely satisfied (the run actually
read the live number, actually listed both call-sites) — the keyword can match text that gestures at the
observation without making it. Tighten a case's `MATCH` signatures in `grade.py` as your phrasing
stabilises.

## Step 5 — run the controls, and keep both numbers
```
./run_case.sh controls/control-01-standard-clone.json runs/control-01   # same blind procedure
python3 grade.py --control controls/control-01-standard-clone.json --run runs/control-01
```
A control should return a **clean verdict + Null Report** with **zero** gate-clearing findings. Count
`FP` (criticals/highs on a clean target) by hand from the transcript. Report the suite as a pair:
**recall** (real cases caught via path) **and FP rate** (criticals per clean run). One without the other
is a lie — a prompt that scores 100% recall and two false criticals per clean target is not good.

## Keeping the suite honest over time
- **Retire leaked cases.** If a case starts scoring a perfect PATH with suspiciously little work in the
  transcript, the model has memorised it — pull it and replace it.
- **Weight toward obscure and recent.** The less a target was written about, the more the score reflects
  derivation. Pull fresh incidents (e.g. from hacked.slowmist.io) and blind them.
- **Rotate.** Re-blind and reorder periodically so a fixed prompt can't be tuned to the fixed suite.

## Authoring a new blind case
1. Pick a recent in-scope incident with a real fork point.
2. Write `blinded_brief` generically — the shape of the system and "find how an unprivileged attacker
   takes value", never the name/date/loss.
3. List `must_reach` as the intermediate **observations** that prove the path was walked (not the
   conclusion). List `must_not` (naming the incident before evidence; reporting a different bug).
4. Put the real story in `answer_for_grader_only`.
5. Add the incident's proper names to `RETRIEVAL` in `grade.py` — then run `run_case.sh` and confirm the
   **leak check passes**, i.e. those names are absent from CORE and the modules. If a name is also in the
   auditor's material, it can't be a recall signal; don't use it as one.
6. Add a `MATCH` entry (one synonym group per `must_reach`) so the grader can score it.
Keep every case's answer strictly disjoint from what the auditor is handed. That disjointness *is* the
blinding.
