"""Offline regression: real RTL, independent codec, lifecycle, no hardware I/O."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    from audit_pins import audit
    audit()
    folder = ROOT / 'build/tests'; folder.mkdir(parents=True, exist_ok=True)
    sys.path.insert(0, str(ROOT / 'host'))
    from protocol import Config, command, decode_status, Stream
    fixture = b''.join((command('config', 1, Config(mode=3, axis=3, angle_kp=20).payload()),
                        command('arm', 2), command('target', 3, Config(mode=4, axis=3).target(1, 60000, 60000)), command('stop', 4)))
    (folder / 'commands.hex').write_text('\n'.join(f'{b:02x}' for b in fixture))
    compiler, runner = shutil.which('iverilog'), shutil.which('vvp')
    if not compiler or not runner: raise SystemExit('Icarus iverilog/vvp required')
    sources = sorted(p for p in (ROOT / 'rtl').rglob('*') if p.suffix in ('.v', '.sv'))
    results = []
    for bench in sorted((ROOT / 'tests').glob('tb_*.sv')):
        image = folder / (bench.stem + '.vvp')
        compile_result = subprocess.run([compiler, '-g2012', '-s', bench.stem, '-o', str(image), *map(str, sources), str(bench)], cwd=ROOT, capture_output=True, text=True)
        if compile_result.returncode: raise RuntimeError(compile_result.stdout + compile_result.stderr)
        result = subprocess.run([runner, str(image)], cwd=ROOT, capture_output=True, text=True, timeout=90)
        output = result.stdout + result.stderr
        (folder / (bench.stem + '.log')).write_text(output, encoding='utf-8')
        print(output.strip())
        if result.returncode or 'PASS' not in output: raise SystemExit(1)
        results.append(bench.stem)
    telemetry = decode_status((folder / 'telemetry.bin').read_bytes())
    expected = dict(pitch_deg=2.5, rate_dps=-3.25, left_position=-123, right_position=456, left_rpm=1, right_rpm=-2,
                    left_pwm=30, right_pwm=-40, left_invalid=7, right_invalid=8, speed_trim_deg=.5,
                    config_sequence=4, interval_us=998, rejected=3, left_cpr=60000, right_cpr=60000,pin_profile='carrier_m2_23_30')
    for name, value in expected.items():
        if telemetry[name] != value: raise AssertionError((name, telemetry[name], value))
    print('PASS RTL UART -> independent Python status CRC and all signed fields')
    stream=Stream();mixed=stream.feed((folder/'imu_mux.bin').read_bytes())
    diagnostics=[r for r in mixed if r.get('_type')=='imu_diagnostics']
    statuses=[r for r in mixed if r.get('_type')!='imu_diagnostics']
    assert stream.bad_crc==0 and len(diagnostics)==2 and len(statuses)>=20
    assert diagnostics[0]['sda_low_permille']==1000 and diagnostics[1]['sda_low_permille']==0
    assert diagnostics[0]['who_am_i']==0x47 and diagnostics[0]['last_error']==1 and diagnostics[0]['az_g']==-1
    assert all(not r['armed'] and r['left_pwm']==r['right_pwm']==0 for r in statuses)
    print('PASS independent IMU/status multiplex CRC, identity, signed axes, stuck-line and recovery decoding')
    subprocess.run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_*.py', '-v'], cwd=ROOT, check=True)
    subprocess.run(['node', '-e', "const fs=require('fs'),vm=require('vm'); const h=fs.readFileSync('host/index.html','utf8'); new vm.Script(h.match(/<script>([\\s\\S]*?)<\\/script>/)[1]); console.log('PASS console JavaScript syntax');"], cwd=ROOT, check=True)
    manifest = json.loads((ROOT / 'docs/reused_sources.json').read_text(encoding='utf-8'))
    for name, record in manifest.items():
        if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != record['sha256']: raise AssertionError('Reused source changed: ' + name)
    report = dict(utc=datetime.now(timezone.utc).isoformat(), rtl_cases=results, passed=True, hardware_tested=False,
                  source_sha256={p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources + list((ROOT / 'host').glob('*')) if p.is_file()})
    (folder / 'result.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('PASS independent project regression; no serial opened, no FPGA programmed, no physical validation claimed.')


if __name__ == '__main__': main()
