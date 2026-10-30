"""Passively capture Balance V2 telemetry; never transmits serial commands."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'balance/host'))
from protocol import Parser
import serial


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--port', required=True)
    ap.add_argument('--seconds', type=float, default=12)
    ap.add_argument('--out', type=Path, required=True)
    a = ap.parse_args()
    if not 1 <= a.seconds <= 300:
        ap.error('seconds must be 1..300')
    a.out.mkdir(parents=True, exist_ok=False)
    parser, rows, raw = Parser(), [], bytearray()
    with serial.Serial(a.port, 921600, timeout=.1) as port:
        port.reset_input_buffer()
        until = time.monotonic() + a.seconds
        while time.monotonic() < until:
            block = port.read(4096)
            raw.extend(block)
            rows.extend(parser.feed(block))
    (a.out / 'serial.bin').write_bytes(raw)
    (a.out / 'records.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')
    summary = dict(packets=len(rows), crc_errors=parser.crc_errors,
                   telemetry_gaps=parser.gaps, serial_tx_bytes=0,
                   raw_sha256=hashlib.sha256(raw).hexdigest())
    if rows:
        elapsed = (rows[-1]['time_us'] - rows[0]['time_us']) & 0xffffffff
        delta = (rows[-1]['imu_seq'] - rows[0]['imu_seq']) & 0xffffffff
        summary.update(raw_rate_hz=delta * 1e6 / elapsed if elapsed else 0,
                       first=rows[0], last=rows[-1],
                       accel_mean=[statistics.mean(r['accel'][i] for r in rows) for i in range(3)])
        for key in ('imu_ok', 'imu_errors', 'imu_invalid', 'imu_last_error',
                    'who_am_i', 'drive', 'running', 'active', 'commissioning'):
            summary[key + '_values'] = sorted({r[key] for r in rows})
        summary['age_us_range'] = [min(r['age_us'] for r in rows), max(r['age_us'] for r in rows)]
    (a.out / 'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
    print(json.dumps(summary, indent=2))
    healthy = rows and all(r['imu_ok'] and r['who_am_i'] == 0x47 and
                          r['imu_errors'] == r['imu_invalid'] == r['imu_last_error'] == 0 and
                          not any(r[k] for k in ('drive', 'running', 'active', 'commissioning'))
                          for r in rows)
    return 0 if healthy and delta and not parser.crc_errors and not parser.gaps else 1


if __name__ == '__main__':
    raise SystemExit(main())
