"""Validate M2 wiring against an exported carrier GPIO reference, without hardware."""
import csv
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def require(value, message):
    if not value: raise ValueError(message)


def top_ports(text):
    match = re.search(r'module\s+brushed_balance_top\s*#\(.*?\)\s*\((.*?)\);', text, re.S)
    require(match, 'Cannot identify top-level port declarations')
    parts = re.split(r'\b(input|output|inout)\s+wire\s*', match[1])
    ports = {}
    for i in range(1, len(parts), 2):
        direction = {'input': 'IN', 'output': 'OUT', 'inout': 'INOUT'}[parts[i]]
        decl = parts[i + 1].strip().rstrip(',').strip()
        vector = re.match(r'\[(\d+):(\d+)\]\s*', decl)
        names = decl[vector.end():] if vector else decl
        for name in names.split(','):
            name = name.strip()
            require(re.fullmatch(r'[A-Za-z_]\w*', name), 'Unknown top declaration: ' + name)
            bits = range(min(int(vector[1]), int(vector[2])), max(int(vector[1]), int(vector[2])) + 1) if vector else [None]
            for bit in bits:
                key = f'{name}[{bit}]' if bit is not None else name
                require(key not in ports, 'Duplicate top port: ' + key)
                ports[key] = direction
    return ports


def audit(rows=None, text=None):
    if rows is None:
        with (ROOT / 'constraints/pins.csv').open(encoding='utf-8-sig') as handle: rows = list(csv.DictReader(handle))
    if text is None: text = (ROOT / 'rtl/brushed_balance_top.sv').read_text(encoding='utf-8')
    require(len(rows) == 30, 'M2 top must have 30 physical pins')
    require(len({r['ball'] for r in rows}) == len(rows), 'Duplicate physical ball')
    require(len({r['signal'] for r in rows}) == len(rows), 'Duplicate logical signal')
    ports = top_ports(text)
    require(set(ports) == {r['signal'] for r in rows}, 'Top-level ports do not exactly match constraints')
    for row in rows: require(ports[row['signal']] == row['direction'], 'Port direction mismatch: ' + row['signal'])
    require('legacy_m2' not in text and 'legacy_cal_disabled' not in text, 'Old M2 output aliases remain')
    profile = json.loads((ROOT / 'constraints/pin_profile.json').read_text(encoding='utf-8'))
    require(profile['id'] == 'carrier_m2_23_30' and profile['ground_pins'] == [21, 22], 'Unexpected carrier profile')
    with (ROOT / 'constraints/carrier_drv2_reference.csv').open(encoding='utf-8') as handle:
        refs = {int(r['drv2_pin']): r for r in csv.DictReader(handle)}
    required = {'left_in1': 25, 'left_in2': 26, 'right_in1': 27, 'right_in2': 28,
                'left_enc_a': 29, 'left_enc_b': 30, 'right_enc_a': 23, 'right_enc_b': 24}
    motors = [r for r in rows if r['group'] == 'chassis']
    require({r['signal'] for r in motors} == set(required), 'Expected four motor outputs and four encoder inputs')
    for row in motors:
        match = re.search(r'\bJ_DRV2-(\d+)\b', row['endpoint'])
        require(match, 'Missing M2 header endpoint: ' + row['signal'])
        pin = int(match[1]);require(pin == required[row['signal']], 'Unexpected M2 assignment: ' + row['signal'])
        ref = refs[pin]
        require(row['ball'] == ref['ball'] and int(row['p7']) == int(ref['p7']), 'Carrier reference disagrees: ' + row['signal'])
        require(row['direction'] == ('IN' if '_enc_' in row['signal'] else 'OUT'), 'Wrong motor/encoder direction')
    require({int(re.search(r'J_DRV2-(\d+)', r['endpoint'])[1]) for r in motors} == set(range(23, 31)), 'Signals must occupy contiguous M2-23..30')
    return dict(pin_profile=profile['id'],physical_pins=len(rows),signals=8,ground_pins=[21,22],hardware_tested=False)


if __name__ == '__main__': print(json.dumps(audit(), indent=2))
