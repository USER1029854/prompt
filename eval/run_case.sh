#!/usr/bin/env bash
# Set up a BLINDED working dir for one case. Never copies the answer into the auditor's view.
set -euo pipefail
CASE="${1:?usage: run_case.sh cases/case-XX.json <workdir>}"
WORK="${2:?give a workdir}"
mkdir -p "$WORK"
python3 - "$CASE" "$WORK" <<'PY'
import json,sys,os
case=json.load(open(sys.argv[1])); work=sys.argv[2]
brief={k:case[k] for k in case if k not in ("must_reach","must_not","answer_for_grader_only","correct_output","fail_if","note_for_grader","expected_verdict")}
open(os.path.join(work,"BRIEF.json"),"w").write(json.dumps(brief,indent=2))
print("Blinded brief written to",os.path.join(work,"BRIEF.json"))
print("\nGive the auditor ONLY:")
print("  - CORE.md")
print("  - modules:",", ".join(case["substrate_modules"]))
print("  - BRIEF.json (above)")
print("  - a fork/replay endpoint pinned ONE unit before the exploit")
print("\nDo NOT paste the incident name, date, or description.")
print("Collect the run into",work,"as transcript.txt (+ manifest.json), then:")
print(f"  python3 grade.py --case {sys.argv[1]} --run {work}")
PY
