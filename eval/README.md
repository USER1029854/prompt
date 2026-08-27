# Testing the prompt against history

You asked whether you could have caught these. This is how you find out without lying to yourself.
The trap is contamination: every famous incident is in the model's weights and one search away, so a
run that names the right bug may have *recalled* it, not *derived* it — and you cannot tell which from
the answer. So this suite scores **the path, not the answer**, weights toward obscure/recent targets,
and includes **clean controls** with no bug so you can measure false positives.

## The three rules

1. **Blind the target.** Hand the auditor a fork at a height/slot/version *one block before* the
   exploit and nothing else — no name, no date, no "there's a bug." For an app-chain that's a height
   + binary version; for a contract, an address; for a bridge, both sides pinned. Strip identifying
   metadata. Do not paste the incident description.

2. **Score `must_reach`, not the finding.** Each case lists the intermediate *observations* that
   constitute having actually walked the path — a live number read, two call sites listed, a field
   noted as unsigned. An auditor that makes those observations will catch the same class on a protocol
   it has never heard of; one that names the incident without them recalled it. Only the path predicts
   performance on the next, unseen system — which is the only thing you actually want to know.
   `must_not` lists the confabulation failure modes: naming the incident with no path, or inventing a
   different bug.

3. **Run clean controls and count false positives.** A prompt that finds a critical on every target
   is worthless. Score each clean control for whether the verdict is correctly clean-with-Null-Report,
   and count reported "findings" per clean run. Track recall (real cases caught via path) **and** FP
   rate (criticals per clean run) — a number without the other is a lie.

## Scoring per case

- **PATH** = fraction of `must_reach` observations the run actually made, cited. This is the score.
- **DERIVED?** = did it reach them from the target, or retrieve from memory? Evidence of retrieval
  (naming the protocol/date before any on-chain observation) caps the case at "recalled," not "found."
- **PROVEN?** = did it produce a fork PoC / executable check, or only reason?
- **FP** (clean controls) = count of reported findings that clear the gate; target 0.

A case is **"could have prevented"** only if PATH ≥ 0.8, DERIVED, and PROVEN. Naming the bug without
the path is a fail, however impressive it reads.

## How to run it
See **RUNBOOK.md** for the concrete blind procedure (set up the fork, assemble and
leak-check the bundle, run a fresh auditor, grade PATH/DERIVED/PROVEN, run the controls).

## Files
- `cases/*.json` — one per historical incident, blinded, with `must_reach` / `must_not` and the
  substrate module(s) to load. `answer` is at the bottom, for the grader only — never in the auditor's
  context.
- `controls/*.json` — targets with no known live exploitable path; the correct output is a clean
  verdict + Null Report.
- `grade.py` — mechanical grader: reads a run's transcript + `manifest.json`, matches `must_reach`
  by evidence tags, emits PATH/DERIVED/PROVEN/FP.
- `run_case.sh` — sets up a blinded working dir for one case (no answer leaked) and prints the exact
  auditor instructions.

## The honest caveat
This measures whether the *method* generalizes, not whether the model has memorized 2026. Weight the
suite toward the most obscure and most recent incidents you can find (pull fresh ones from
hacked.slowmist.io), rotate them, and re-blind. When a case starts scoring perfectly on PATH with
suspiciously little work, it has leaked — retire it.
