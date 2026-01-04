#!/usr/bin/env python3
import json
from pathlib import Path

decoded_path = Path('assets/programs/Programs_decoded_full.json')
ui_path = Path('assets/programs.json')

decoded = json.loads(decoded_path.read_text(encoding='utf-8'))
ui = json.loads(ui_path.read_text(encoding='utf-8'))

by_uuid = {e.get('ProgramUUID'): e for e in decoded if e.get('ProgramUUID')}
by_int  = {e.get('internalID'): e for e in decoded if e.get('internalID') is not None}

def iter_ui_programs(ui_obj):
    for cat in ui_obj.get('categories', []):
        for p in cat.get('programs', []):
            yield p
        for sub in cat.get('subcategories', []):
            for p in sub.get('programs', []):
                yield p

updated = 0
not_found = 0

for p in iter_ui_programs(ui):
    uuid = p.get('uuid')
    iid = p.get('internalId') if p.get('internalId') is not None else p.get('internalID')

    entry = None
    if uuid and uuid in by_uuid:
        entry = by_uuid[uuid]
    elif iid is not None:
        try:
            entry = by_int.get(int(iid))
        except Exception:
            entry = None

    if entry is None:
        not_found += 1
        continue

    lvl = entry.get('level')
    if lvl is None:
        continue
    try:
        lvl_int = int(str(lvl))
    except Exception:
        continue

    p['level'] = lvl_int
    updated += 1

bak = ui_path.with_suffix('.json.bak')
bak.write_text(ui_path.read_text(encoding='utf-8'), encoding='utf-8')
ui_path.write_text(json.dumps(ui, ensure_ascii=False, indent=2) + "\n", encoding='utf-8')

print("Backup written:", bak)
print("Programs updated with level:", updated)
print("Programs without decoded match:", not_found)
