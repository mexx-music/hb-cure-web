#!/usr/bin/env python3
import json, re
from pathlib import Path

decoded_path = Path('assets/programs/Programs_decoded_full.json')
ui_path = Path('assets/programs.json')

decoded = json.loads(decoded_path.read_text(encoding='utf-8'))
ui = json.loads(ui_path.read_text(encoding='utf-8'))

# collect existing UI programs
def collect_ui_programs(ui_obj):
    arr=[]
    for cat in ui_obj.get('categories', []):
        arr += cat.get('programs', [])
        for sub in cat.get('subcategories', []):
            arr += sub.get('programs', [])
    return arr

ui_programs = collect_ui_programs(ui)
ui_uuids = {p.get('uuid') for p in ui_programs if p.get('uuid')}
ui_ints = set()
for p in ui_programs:
    iid = p.get('internalId') if p.get('internalId') is not None else p.get('internalID')
    if iid is None: 
        continue
    try:
        ui_ints.add(int(iid))
    except:
        pass

# decoded lookups
def to_int(x):
    try: return int(x)
    except: return None

def slugify_uuid(u: str) -> str:
    # stable, short-ish slug
    u = u.lower()
    u = re.sub(r'[^a-z0-9]+', '_', u)
    return f"adv_{u[:8]}_{u[-4:]}"

add_items = []
for e in decoded:
    uuid = e.get('ProgramUUID')
    iid = to_int(e.get('internalID'))
    lvl = to_int(e.get('level'))
    if uuid is None or lvl is None:
        continue
    if lvl < 2:
        continue
    if (uuid in ui_uuids) or (iid is not None and iid in ui_ints):
        continue
    add_items.append({
        "id": slugify_uuid(uuid),
        "name": e.get('ProgramEN') or e.get('ProgramDE') or "Program",
        "uuid": uuid,
        "internalId": iid,
        "level": lvl
    })

# ensure category exists
cats = ui.setdefault('categories', [])
cat_id = "advanced_expert"
target = None
for c in cats:
    if c.get('id') == cat_id:
        target = c
        break
if target is None:
    target = {
        "id": cat_id,
        "title": "Advanced / Expert",
        "subcategories": [],
        "programs": []
    }
    cats.append(target)

# add programs (avoid duplicates)
existing_ids = {p.get('id') for p in target.get('programs', [])}
added = 0
for p in add_items:
    if p["id"] in existing_ids:
        continue
    target["programs"].append(p)
    added += 1

# backup + write
bak = ui_path.with_suffix('.json.bak2')
bak.write_text(ui_path.read_text(encoding='utf-8'), encoding='utf-8')
ui_path.write_text(json.dumps(ui, ensure_ascii=False, indent=2) + "\n", encoding='utf-8')

print("Backup written:", bak)
print("Added advanced/expert programs:", added)
print("Total candidates (lvl>=2 missing):", len(add_items))
