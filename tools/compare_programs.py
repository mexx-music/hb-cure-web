#!/usr/bin/env python3
import json
from pathlib import Path
from collections import Counter, defaultdict

repo = Path.cwd()
decoded_path = repo / 'assets' / 'programs' / 'Programs_decoded_full.json'
ui_path = repo / 'assets' / 'programs.json'

def load_strip_comments(p: Path):
    s = p.read_text(encoding='utf-8')
    lines = []
    for ln in s.splitlines():
        stripped = ln.strip()
        if stripped.startswith('//'):
            continue
        lines.append(ln)
    return json.loads('\n'.join(lines))

if not decoded_path.exists():
    print('ERROR: Programs_decoded_full.json not found at', decoded_path)
    raise SystemExit(1)

if not ui_path.exists():
    print('ERROR: programs.json not found at', ui_path)
    raise SystemExit(1)

decoded = load_strip_comments(decoded_path)
ui = load_strip_comments(ui_path)

total_decoded = len(decoded)

ui_programs = []
for cat in ui.get('categories', []):
    for p in cat.get('programs', []):
        ui_programs.append(p)
    for sub in cat.get('subcategories', []):
        for p in sub.get('programs', []):
            ui_programs.append(p)

total_ui = len(ui_programs)

decoded_by_uuid = {e.get('ProgramUUID'): e for e in decoded if e.get('ProgramUUID')}
decoded_by_internal = {e.get('internalID'): e for e in decoded if e.get('internalID') is not None}

ui_by_uuid = {p.get('uuid'): p for p in ui_programs if p.get('uuid')}
ui_by_internal = {}
for p in ui_programs:
    iid = p.get('internalId') or p.get('internalID')
    if iid is not None:
        try:
            ui_by_internal[int(iid)] = p
        except ValueError:
            pass

missing_decoded = []
for uuid, entry in decoded_by_uuid.items():
    iid = entry.get('internalID')
    if (uuid not in ui_by_uuid) and (iid not in ui_by_internal):
        missing_decoded.append({
            'uuid': uuid,
            'internalID': iid,
            'level': entry.get('level')
        })

level_counts = Counter()
for e in missing_decoded:
    level_counts[e.get('level')] += 1

print('--- Program Catalog Comparison Report ---')
print('Total programs in Programs_decoded_full.json:', total_decoded)
print('Total program entries found in assets/programs.json (catalog):', total_ui)
print('Decoded entries NOT referenced in UI:', len(missing_decoded))
for lvl in sorted(level_counts):
    print(f'  level {lvl}: {level_counts[lvl]}')
print('--- end report ---')
