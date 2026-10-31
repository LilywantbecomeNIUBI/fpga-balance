"""Read-only source, pin and preset check; no serial and no FPGA programming."""
import csv
import hashlib
import json
from pathlib import Path
import sys
from audit_pins import audit

ROOT = Path(__file__).resolve().parents[1]


def main():
    manifest = json.loads((ROOT / 'SOURCE_MANIFEST.json').read_text(encoding='utf-8'))
    for name, digest in manifest['sha256'].items():
        path = (ROOT / name).resolve()
        if not path.is_relative_to(ROOT) or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise SystemExit('Changed or missing source: ' + name)
    pin_audit = audit()
    sys.path.insert(0, str(ROOT / 'host'))
    from protocol import Config
    for path in (ROOT / 'config').glob('*.json'):
        if path.name != 'motors.json': Config(**json.loads(path.read_text(encoding='utf-8'))).payload()
    for name, record in json.loads((ROOT / 'docs/reused_sources.json').read_text(encoding='utf-8')).items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == record['sha256']
    print('PASS: source manifest, '+str(pin_audit['physical_pins'])+' unique physical pins, contiguous M2 wiring, all staged presets, exact reused sources.')
    print('No serial port opened; no FPGA programmed; no motor commands.')


if __name__ == '__main__': main()
