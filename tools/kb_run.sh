#!/usr/bin/env bash
# Full Knowledge Base pipeline: rebuild seeds -> validate -> manifest -> export.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== 1/5 rebuild structured collections =="
node tools/extract_site_data.js
python3 tools/build_academy_catalog.py
python3 tools/seed_general_trading.py
python3 tools/seed_general_mechanics.py
python3 tools/seed_mt_concepts.py
python3 tools/seed_mt_common.py
python3 tools/seed_mt5.py
python3 tools/seed_mt4.py
python3 tools/seed_mt_troubleshooting.py
python3 tools/seed_mt_comparison.py
python3 tools/seed_psychology.py
python3 tools/seed_psychology_safety.py
python3 tools/seed_lesson_intro_01.py
python3 tools/seed_lesson_intro_02.py
python3 tools/seed_lesson_intro_03.py
python3 tools/seed_lesson_psychology_p01.py
python3 tools/seed_academy_policies.py
python3 tools/seed_governance.py

echo "== 2/5 validate =="
python3 tools/kb_validate.py

echo "== 3/5 manifest =="
python3 tools/kb_build_manifest.py

echo "== 4/5 export =="
python3 tools/kb_export.py

echo "== 5/5 coverage report =="
python3 tools/mt_coverage_report.py
