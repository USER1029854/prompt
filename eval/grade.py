#!/usr/bin/env python3
"""
Mechanical grader for a blinded audit run.

Scores the PATH (did the run make the must_reach observations?), not the answer.
Detects likely RETRIEVAL (named the incident before any on-chain evidence).
Counts FALSE POSITIVES on clean controls.

This grades structure, not prose truth — it tells you whether the run *did the work*,
which is what predicts performance on the next, unseen target. A human still confirms
each matched observation is real. Usage:

  grade.py --case cases/case-02-governance-capture.json --run <run_dir>

<run_dir> must contain:
  transcript.txt  — the full auditor output
  manifest.json   — {claim_id: [evidence_file, ...]} the run produced (optional but recommended)

The grader matches each must_reach item by keyword signature against the transcript AND
checks that at least one cited evidence file exists (proof of work, not just words).
Edit MATCH below per case as your phrasing stabilizes; the defaults are deliberately loose
so you tighten toward your own runs rather than fight a guess.
"""
import argparse, json, os, re, sys

def load(p):
    with open(p) as f: return json.load(f)

def transcript(run_dir):
    p = os.path.join(run_dir, "transcript.txt")
    if not os.path.exists(p):
        print(f"! no transcript.txt in {run_dir}", file=sys.stderr); return ""
    return open(p, errors="replace").read().lower()

def manifest_files_exist(run_dir):
    p = os.path.join(run_dir, "manifest.json")
    if not os.path.exists(p): return None
    m = load(p); missing = []
    for cid, files in m.items():
        fl = files if isinstance(files, list) else [files]
        for f in fl:
            if not (os.path.exists(f) or os.path.exists(os.path.join(run_dir, f))):
                missing.append((cid, f))
    return missing

# Loose keyword signatures per must_reach index, keyed by case id.
# A must_reach item is HIT if any of its signature groups is fully present (all terms in a group).
MATCH = {
 "case-01": [["precompile"],
             ["nested","recursive","inner context","call context"],
             ["same balance","twice","double-spend","double spend","reused","spent twice"],
             ["advisory","cve","ghsa","version pinned","unapplied"],
             ["flash","unprivileged","ordinary account","permissionless"]],
 "case-02": [["total supply","totalsupply","float","voting token supply","voting power supply"],
             ["cost","$","acquire","buy majority","price of control"],
             ["cooldown","reconfigur","enable itself","self-enable","self-elevat","delay owner","delay.owner"],
             ["acquirable","cheap","permissionless","cheaply acquire"],
             ["warp","vm.warp","advance","fast-forward","roll","jump the clock","skip the delay"]],
 "case-03": [["slot0","spot","getreserves","instantaneous"],
             ["twap","deviation","time-averaged","time weighted"],
             ["mint","burn","deposit/withdraw","user path"],
             ["flash","manipulat"],
             ["poc","net positive","fork","assertge"]],
 "case-04": [["attestation","signature","signed message","proof"],
             ["burn","lock","not backed","never happened","no real deposit","baseless"],
             ["sender","recipient","hookdata","canonical messenger"],
             ["forged","forge a message","fabricat"],
             ["mint","lock","reconcil","supply vs custody","conserv"]],
 "case-05": [["owner check","owner-check","owner validation","owns the account"],
             ["signer","pda","identity","substitut","expected account"],
             ["overflow","checked","wrapping","release build"],
             ["accountinfo","malicious account","wrong owner","substituted account","fake account"],
             ["bankrun","litesvm","forked validator","harness","test-validator"]],
 "case-06": [["fixed-point","liquidity math","math helper","clmm","sqrt","tick","core math"],
             ["shift","<<",">>","cast","truncat","narrow"],
             ["boundary","edge","threshold","overflow check","bounds check"],
             ["mint","liquidity","credit","deposit"],
             ["fuzz","assertge","prover","monotonic","invariant test"]],
 "case-07": [["proof verifies","valid proof","verifier","attestation"],
             ["public input","unconstrained","recipient","amount","nullifier","root","field"],
             ["verifying key","trusted root","not attacker","expected"],
             ["misconfigur","unconstrained","forge","accepts"],
             ["poc","fork","drain","construct a proof"]],
}

RETRIEVAL = ["term finance","aragon","zodiac","arrakis","g-uni","allbridge","cctp","maya","mayachain",
             "cosmos evm","saga","mantra","tac","kiichain","wormhole","gravity bridge","chia","cetus","balancer","foom","sui","aftermath","moonwell","venus"]

def any_syn(group, text):
    # group = list of synonym substrings; HIT iff any synonym appears in text.
    return any(term in text for term in group)

def grade_case(case, run_dir):
    t = transcript(run_dir); cid = case["id"]
    sigs = MATCH.get(cid, [])
    reached = []
    for i, item in enumerate(case["must_reach"]):
        s = sigs[i] if i < len(sigs) else [w for w in re.findall(r"[a-z]{5,}", item.lower())[:3]]
        reached.append(any_syn(s, t))
    path = sum(reached)/len(reached) if reached else 0
    # retrieval detection: incident name appears before the first evidence-ish marker
    first_ev = min([t.find(m) for m in ["0x","block ","height ","slot ","cast ","forge ","live state","totalsupply"] if t.find(m)>=0] or [len(t)])
    retrieved = any((t.find(n)>=0 and t.find(n) < first_ev) for n in RETRIEVAL)
    proven = any(w in t for w in ["poc","forge test","assertge","assert(","bankrun","litesvm","fork-block","--fork"])
    missing = manifest_files_exist(run_dir)
    print(f"\n=== {cid} ({'clean control' if case.get('expected_verdict')=='clean' else 'exploit case'}) ===")
    for i,(item,ok) in enumerate(zip(case["must_reach"], reached)):
        print(f"  [{'X' if ok else ' '}] must_reach[{i}]: {item[:88]}")
    print(f"  PATH   : {path:.2f}  ({sum(reached)}/{len(reached)})")
    print(f"  DERIVED: {'NO — incident named before evidence (likely retrieval)' if retrieved else 'yes (no early incident-naming)'}")
    print(f"  PROVEN : {'yes' if proven else 'no — no fork/PoC/assertion detected'}")
    if missing is None: print("  MANIFEST: none provided")
    elif missing:       print(f"  MANIFEST: {len(missing)} cited files MISSING (claims unbacked) -> {missing[:3]}")
    else:               print("  MANIFEST: all cited files present")
    verdict = "COULD-HAVE-PREVENTED" if (path>=0.8 and not retrieved and proven) else \
              ("RECALLED-NOT-DERIVED" if (path>=0.8 and retrieved) else "MISS")
    print(f"  RESULT : {verdict}")
    return verdict

def grade_control(ctrl, run_dir):
    t = transcript(run_dir)
    clean = ("clean" in t or "no finding" in t or "no exploitable" in t)
    null_report = ("null report" in t or "where i" in t and "wrong" in t) or "most likely" in t
    # crude FP proxy: count 'critical'/'high' finding headers
    fp = len(re.findall(r"\b(critical|high)\b", t))
    print(f"\n=== {ctrl['id']} (CLEAN CONTROL) ===")
    print(f"  VERDICT CLEAN : {'yes' if clean else 'NO — reported a finding on a clean target'}")
    print(f"  NULL REPORT   : {'present' if null_report else 'MISSING (required on clean verdict)'}")
    print(f"  FP PROXY      : {fp} occurrences of critical/high (inspect each; target 0 gate-clearing)")
    print(f"  RESULT        : {'PASS' if (clean and null_report) else 'FAIL'}  (confirm FP count by hand)")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--case"); ap.add_argument("--control"); ap.add_argument("--run", required=True)
    a = ap.parse_args()
    if a.case:    grade_case(load(a.case), a.run)
    elif a.control: grade_control(load(a.control), a.run)
    else: print("give --case or --control"); sys.exit(2)

if __name__ == "__main__": main()
