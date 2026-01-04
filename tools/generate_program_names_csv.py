#!/usr/bin/env python3
import json
import csv
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent  # repo root (tools/../)
SRC = ROOT / 'assets' / 'programs' / 'Programs_decoded_full.json'
DST = ROOT / 'assets' / 'program_names_DE_EN.csv'
DEBUG = True

if not SRC.exists():
    print(f'ERROR: source file not found: {SRC}', file=sys.stderr)
    print(f'Current working dir: {Path.cwd()}', file=sys.stderr)
    sys.exit(2)

with SRC.open('r', encoding='utf-8') as f:
    data = json.load(f)
    if DEBUG:
        print(f'Loaded {len(data)} top-level entries from {SRC}', file=sys.stderr)

pairs = []
for item in data:
    prog = item.get('Program') if isinstance(item, dict) else None
    if not prog or not isinstance(prog, dict):
        continue
    en = prog.get('EN')
    de = prog.get('DE')
    if en is None or de is None:
        continue
    en_s = str(en).strip()
    de_s = str(de).strip()
    if not en_s or not de_s:
        continue
    pairs.append((de_s, en_s))

# Deduplicate while preserving first occurrence
seen = {}
for de, en in pairs:
    key = (de, en)
    if key not in seen:
        seen[key] = None
unique_pairs = list(seen.keys())

# Sort alphabetically by EN (case-insensitive), stable for equal EN
unique_pairs.sort(key=lambda p: p[1].casefold())

# Write CSV with semicolon delimiter, UTF-8
with DST.open('w', encoding='utf-8', newline='') as f:
    writer = csv.writer(f, delimiter=';')
    writer.writerow(['DE', 'EN'])
    for de, en in unique_pairs:
        writer.writerow([de, en])
if DEBUG:
    print(f'Wrote CSV to {DST}', file=sys.stderr)

# Write a small sidecar file containing the count (makes it easy to read programmatically)
count_file = DST.with_suffix(DST.suffix + '.count')
count_file.write_text(str(len(unique_pairs)), encoding='utf-8')
if DEBUG:
    print(f'Wrote count to {count_file}', file=sys.stderr)

# Print summary
print(f'WROTE_ROWS:{len(unique_pairs)}')

# Check if file is listed in pubspec.yaml
pubspec = ROOT / 'pubspec.yaml'
included = False
if pubspec.exists():
    txt = pubspec.read_text(encoding='utf-8')
    if 'assets/program_names_DE_EN.csv' in txt:
        included = True

print(f'CSV_PATH:{DST}')
print(f'IN_PUBSPEC:{included}')
