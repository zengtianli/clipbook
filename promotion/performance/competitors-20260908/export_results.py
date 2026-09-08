"""Export local raw measurements without clipboard contents or credentials."""
from pathlib import Path
import csv, hashlib, json

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
BUILD = REPO/'build/competitor-benchmark'
rows = []
for line in (BUILD/'samples.jsonl').read_text().splitlines():
    r = json.loads(line)
    if 'cpu_timebase_factor' not in r:
        for k in ('start','end'):
            r[k]['cpu_seconds'] *= 125/3
        r['cpu_percent_one_core'] *= 125/3
        r['cpu_timebase_factor'] = 125/3
        r['cpu_corrected_from_raw_mach_ticks'] = True
    if r['stage'] == 'Deck-fresh-100-text-20-images-background-no-panel':
        r['original_stage_label'] = r['stage']
        r['stage'] = 'Deck-62-text-16-images-background-no-panel'
        r['correction'] = 'Actual SQLite count was 62 text + 16 PNG, not the sent 100 + 20.'
    if r['stage'] == 'Deck-100-text-20-images-background-no-panel':
        r['original_stage_label'] = r['stage']
        r['stage'] = 'Deck-66-text-18-images-background-no-panel'
        r['correction'] = 'SQLite still had only 66 text + 18 PNG after replay; exclude from matched-data comparison.'
    rows.append(r)
(HERE/'samples.json').write_text(json.dumps(rows,indent=2,ensure_ascii=False)+'\n')
with (HERE/'samples.csv').open('w',newline='') as f:
    w=csv.writer(f)
    w.writerow(['stage','memory_start_MiB','memory_end_MiB','CPU_percent_one_core','seconds'])
    for r in rows:
        w.writerow([r['stage'],r['start']['footprint_MiB'],r['end']['footprint_MiB'],r['cpu_percent_one_core'],r['wall_seconds']])
(HERE/'image-fixture-hashes.json').write_text(json.dumps([
    {'file':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size}
    for p in sorted((BUILD/'image-fixtures').glob('*.png'))],indent=2)+'\n')
print(f'Exported {len(rows)} samples')
