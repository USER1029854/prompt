#!/usr/bin/env python3
"""
Harness self-test — proves the EVAL MACHINERY is wired correctly, for every case.

This does NOT run an auditor and does NOT tell you whether CORE.md finds bugs — that needs a real
fork and a fresh agent per case (see HOWTO-case-10.md / RUNBOOK.md). What it proves, in seconds and
with no network, is that the plumbing around that run is sound:

  1. BLIND    — run_case.sh emits a BRIEF with only whitelisted keys (no class/note/answer leaking).
  2. LEAKCHK  — the leak check verdict is what the case expects (PASS, or WARN on known framework names).
  3. ALIGN    — grade.py has a MATCH signature whose group-count equals the case's must_reach count.
  4. DISCRIM  — the grader SEPARATES a walked-the-path transcript from a did-nothing one:
                a synthetic POSITIVE transcript (built from each signature group) scores COULD-HAVE-PREVENTED,
                a synthetic NEGATIVE transcript (generic "clean") scores MISS. A grader that can't tell
                these apart is broken, and this is the check that catches a rubber-stamp signature.
  5. RETRIEVE — a transcript that NAMES the incident before any evidence trips DERIVED=NO (retrieval flag live).
  6. CONTROL  — for controls, a clean+null-report transcript PASSES and a 'critical!' transcript raises the FP proxy.

A synthetic positive is NOT evidence CORE works; it is evidence the grader would REGISTER the work if a
real auditor did it. Read this as a preflight, never as a score.
"""
import json, os, re, subprocess, sys, tempfile, glob

HERE = os.path.dirname(os.path.abspath(__file__))
def sh(*a):
    return subprocess.run(a, cwd=HERE, capture_output=True, text=True)

def grade_case(case_path, run_dir):
    r = sh("python3", "grade.py", "--case", case_path, "--run", run_dir)
    return r.stdout + r.stderr
def grade_control(case_path, run_dir):
    r = sh("python3", "grade.py", "--control", case_path, "--run", run_dir)
    return r.stdout + r.stderr

def field(txt, key):
    m = re.search(rf"{key}\s*:\s*(.+)", txt)
    return m.group(1).strip() if m else "?"

import grade  # for MATCH signatures + RETRIEVAL

def make_run(tmp, transcript, with_manifest=True):
    d = os.path.join(tmp, "run"); os.makedirs(d, exist_ok=True)
    open(os.path.join(d, "transcript.txt"), "w").write(transcript)
    if with_manifest:
        # cite a file that exists so MANIFEST doesn't report missing
        open(os.path.join(d, "ev.txt"), "w").write("evidence")
        json.dump({"CLAIM-1": ["ev.txt"]}, open(os.path.join(d, "manifest.json"), "w"))
    return d

EVID = " 0x1234 block 100 cast call forge test assertGe(after,before) poc --fork "  # evidence + proven markers, early
PASS_CASES = 0; FAIL = []

cases = sorted(glob.glob(os.path.join(HERE, "cases", "*.json")))
controls = sorted(glob.glob(os.path.join(HERE, "controls", "*.json")))

print("="*78)
print("HARNESS SELF-TEST  —  machinery only, NOT a measure of whether CORE finds bugs")
print("="*78)

for cp in cases:
    case = json.load(open(cp)); cid = case["id"]; probs = []

    # --- 1/2 BLIND + LEAKCHK: run_case.sh, inspect BRIEF + leak verdict
    with tempfile.TemporaryDirectory() as tmp:
        rc = sh("./run_case.sh", os.path.relpath(cp, HERE), os.path.join(tmp, "w"))
        out = rc.stdout + rc.stderr
        brief_path = os.path.join(tmp, "w", "BRIEF.json")
        if os.path.exists(brief_path):
            keys = set(json.load(open(brief_path)))
            leaked = keys - {"id", "substrate_modules", "blinded_brief"}
            if leaked: probs.append(f"BLIND: brief leaks {leaked}")
        else:
            probs.append("BLIND: no BRIEF.json produced")
        if "LEAK CHECK: FAILED" in out: probs.append("LEAKCHK: hard leak (incident name/grader field in bundle)")

    # --- 3 ALIGN
    sig = grade.MATCH.get(cid)
    if sig is None: probs.append("ALIGN: no MATCH signature")
    elif len(sig) != len(case["must_reach"]): probs.append(f"ALIGN: {len(sig)} sig groups vs {len(case['must_reach'])} must_reach")

    # --- 4 DISCRIM: positive vs negative transcript
    if sig:
        pos = EVID + " ".join(g[0] for g in sig) + " " + " ".join(g[0] for g in sig)
        neg = "Audit complete. No exploitable path was found. The deployment appears sound. Null report: three places a missed issue would live."
        with tempfile.TemporaryDirectory() as tmp:
            gp = grade_case(os.path.relpath(cp, HERE), make_run(tmp, pos))
        with tempfile.TemporaryDirectory() as tmp:
            gn = grade_case(os.path.relpath(cp, HERE), make_run(tmp, neg, with_manifest=False))
        rp, rn = field(gp, "RESULT"), field(gn, "RESULT")
        if rp != "COULD-HAVE-PREVENTED": probs.append(f"DISCRIM: positive oracle scored {rp} (PATH {field(gp,'PATH')}) — expected COULD-HAVE-PREVENTED")
        if rn == "COULD-HAVE-PREVENTED": probs.append(f"DISCRIM: negative oracle scored COULD-HAVE-PREVENTED (grader rubber-stamps)")

    # --- 5 RETRIEVE: an incident name before evidence must trip DERIVED
    ans = case.get("answer_for_grader_only", "").lower()
    name = next((n for n in grade.RETRIEVAL if re.search(r"\b"+re.escape(n)+r"\b", ans)), None)
    if name and sig:
        retr = f"This is the {name} incident. " + EVID + " ".join(g[0] for g in sig)
        with tempfile.TemporaryDirectory() as tmp:
            gr = grade_case(os.path.relpath(cp, HERE), make_run(tmp, retr))
        if "NO" not in field(gr, "DERIVED"): probs.append(f"RETRIEVE: naming '{name}' before evidence did NOT trip DERIVED")

    if probs: FAIL.append((cid, probs)); print(f"[FAIL] {cid}"); [print(f"        - {p}") for p in probs]
    else: PASS_CASES += 1; print(f"[ ok ] {cid}   blind - leakcheck - align({len(sig)}) - discrim - retrieval")

# --- 6 CONTROL
for cp in controls:
    ctrl = json.load(open(cp)); cid = ctrl["id"]; probs = []
    clean = "Audit complete. The result is clean; no exploitable path. Null report: the three places a missed bug would most likely live are ..."
    with tempfile.TemporaryDirectory() as tmp:
        gc = grade_control(os.path.relpath(cp, HERE), make_run(tmp, clean, with_manifest=False))
    if field(gc, "RESULT").split()[0] != "PASS": probs.append(f"CONTROL: clean+null transcript did not PASS ({field(gc,'RESULT')})")
    fp = "Finding: CRITICAL. attacker drains funds. Another HIGH severity issue."
    with tempfile.TemporaryDirectory() as tmp:
        gf = grade_control(os.path.relpath(cp, HERE), make_run(tmp, fp, with_manifest=False))
    if field(gf, "FP PROXY").split()[0] == "0": probs.append("CONTROL: 'critical/high' transcript did not raise FP proxy")
    if probs: FAIL.append((cid, probs)); print(f"[FAIL] {cid}"); [print(f"        - {p}") for p in probs]
    else: print(f"[ ok ] {cid}   clean-passes - fp-proxy-fires")

print("-"*78)
print(f"cases ok: {PASS_CASES}/{len(cases)}   controls ok: {len(controls)-sum(1 for c,_ in FAIL if c.startswith('control'))}/{len(controls)}")
if FAIL:
    print(f"\nSELF-TEST FAILED: {len(FAIL)} item(s) above. The harness is miswired — fix before running auditors.")
    sys.exit(1)
print("\nSELF-TEST PASSED — the machinery is sound for every case.")
print("Reminder: this proves the PLUMBING, not that CORE.md finds bugs. For that, run a real")
print("auditor against a fork per HOWTO-case-10.md and grade the real transcript.")
