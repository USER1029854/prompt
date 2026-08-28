#!/usr/bin/env bash
# Blind-run setup for one eval case:
#   1. writes BRIEF.json  (the case with every answer field stripped)
#   2. assembles PROMPT_BUNDLE.md = CORE.md + the named module(s) + the blinded brief
#      — this is the ONLY thing the auditor may see
#   3. leak-checks the bundle: refuses if any incident name or grader-only field is present
# Usage: ./run_case.sh cases/case-02-governance-capture.json runs/case-02
set -euo pipefail
CASE="${1:?usage: run_case.sh cases/case-XX.json <workdir>}"
WORK="${2:?give a workdir}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"      # repo root (has CORE.md + modules/)
mkdir -p "$WORK"

python3 - "$CASE" "$WORK" "$ROOT" <<'PY'
import json,sys,os,re
case_path,work,root=sys.argv[1],sys.argv[2],sys.argv[3]
case=json.load(open(case_path))

# WHITELIST, not blacklist. A blinding harness must fail closed: anything not explicitly
# cleared for the auditor stays out. (A blacklist silently shipped `class` and `note` — the
# bug class in plain words — to the auditor while the leak check, which screens only incident
# names and grader fields, reported PASS.)
BRIEF_FIELDS=("id","substrate_modules","blinded_brief")
OPERATOR_FIELDS=("class","note","must_reach","must_not","answer_for_grader_only",
                 "correct_output","fail_if","note_for_grader","expected_verdict")
brief={k:case[k] for k in BRIEF_FIELDS if k in case}
unknown=[k for k in case if k not in BRIEF_FIELDS and k not in OPERATOR_FIELDS]
if unknown:
    print("!! case has unrecognised field(s), withheld from the auditor:",", ".join(unknown))
    print("   add each to BRIEF_FIELDS (auditor may see) or OPERATOR_FIELDS (must not) in run_case.sh")
open(os.path.join(work,"BRIEF.json"),"w").write(json.dumps(brief,indent=2))

# assemble the bundle the auditor is allowed to see
mods=case.get("substrate_modules",[])
parts=[("CORE.md",open(os.path.join(root,"CORE.md")).read())]
for m in mods:
    mp=os.path.join(root,"modules",m)
    if not os.path.exists(mp):
        print("!! module not found:",m); sys.exit(2)
    parts.append((f"modules/{m}",open(mp).read()))
parts.append(("BRIEF.json (the blinded target)",json.dumps(brief,indent=2)))
bundle="\n\n".join(f"===== {name} =====\n{body}" for name,body in parts)
bpath=os.path.join(work,"PROMPT_BUNDLE.md")
open(bpath,"w").write(bundle)

# --- leak check: nothing that names the incident may be in what the auditor sees ---
# incident names come from the grader's curated retrieval list (single source of truth)
sys.path.insert(0,os.path.dirname(os.path.abspath(case_path)) or ".")
sys.path.insert(0,os.path.join(root,"eval"))
try:
    from grade import RETRIEVAL
except Exception:
    RETRIEVAL=[]
low=bundle.lower()
hard=[]
for n in RETRIEVAL:
    if re.search(r"\b"+re.escape(n)+r"\b",low): hard.append(("incident-name",n))
for marker in ("answer_for_grader_only","must_reach","must_not","expected_verdict",
               "note_for_grader","correct_output","fail_if"):
    if marker in bundle: hard.append(("grader-field",marker))
# soft: capitalised proper-nouns (len>=5) from the answer that show up in the bundle
ans=case.get("answer_for_grader_only","")
STOP={"Bridge","Oracle","Governance","Protocol","Finance","Network","Vault","Token",
      "Contract","Solana","Cosmos","Ethereum","Attacker","Balance","Signature","Reserve",
      # generic sentence-starters / plain English — flagging these trains you to ignore the warn channel
      "Found","Generalizes","Note","Notes","Where","Their","These","Which","While","Because",
      "Every","Under","After","Before","There","Since","Given","Router","Swap","Swaps",
      "Highest","Deliberately","Connect","Conservation","Delay","Roles","Voting","Compare","Exploit","Target","Ethereum","October","Curve","Finance","Module","Vaults","Vault","Zodiac","Gnosis","Yearn","Governor","August","Tornado"}
soft=[]
for tok in sorted(set(re.findall(r"\b[A-Z][A-Za-z0-9]{4,}\b",ans))):
    if tok in STOP: continue
    if re.search(r"\b"+re.escape(tok.lower())+r"\b",low): soft.append(tok)

print("BRIEF.json + PROMPT_BUNDLE.md written to",work)
if hard:
    print("\n LEAK CHECK: FAILED — the bundle names the incident. Do NOT use it blind:")
    for kind,tok in hard: print(f"    [{kind}] {tok}")
    print("  (fix the case's blinded_brief or the CORE/module text, then re-run.)")
    sys.exit(1)
if soft:
    print("\n LEAK CHECK: WARN — capitalised answer tokens also appear in the bundle (may be coincidental):")
    for tok in soft: print(f"    ? {tok}")
    print("  Confirm these are generic words, not the incident's name, before running blind.")
else:
    print("\n LEAK CHECK: PASS — no incident name or grader field in the bundle.")

print("\nNow, in a FRESH auditor context (new session / new agent, no web-search of the incident,")
print("no ANALYSIS.md, no case file):")
print(f"   hand it ONLY  {bpath}")
print("   plus a fork/replay endpoint pinned ONE unit before the exploit (see RUNBOOK.md step 1)")
print(f"   save its complete output to  {os.path.join(work,'transcript.txt')}  (+ manifest.json if it wrote one)")
print(f"\nThen grade (grader may see the answer; the auditor may not):")
print(f"   python3 grade.py --case {case_path} --run {work}")
PY
