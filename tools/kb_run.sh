#!/usr/bin/env bash
# Full Knowledge Base pipeline: rebuild seeds -> validate -> manifest -> export.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== 1/4 rebuild structured collections =="
node tools/extract_site_data.js
python3 tools/build_academy_catalog.py
python3 tools/seed_general_trading.py
python3 tools/seed_metatrader.py
python3 tools/seed_psychology.py
python3 tools/seed_governance.py

echo "== 2/4 validate =="
python3 tools/kb_validate.py

echo "== 3/4 manifest =="
python3 tools/kb_build_manifest.py

echo "== 4/4 export =="
python3 tools/kb_export.py
