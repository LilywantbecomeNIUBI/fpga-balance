"""Independent Gowin project. No sibling paths, board programming or serial I/O."""
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET
try:
    from .audit_pins import audit
except ImportError:
    from audit_pins import audit

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def grounded_outputs(text):
    """Read OBUF connections, handling both plain bus bits and escaped names."""
    result = {}
    for match in re.finditer(r'(?m)^\s*OBUF\s+\S+\s*\((.*?)\);', text, re.S):
        output = re.search(r'\.O\(\s*(.*?)\s*\)', match[1])
        source = re.search(r'\.I\(\s*(.*?)\s*\)', match[1])
        if output and source: result[output[1].lstrip('\\').strip()] = source[1].strip() == 'GND'
    return result


def prepare(profile='observe', encoder='p30_gmr'):
    pin_audit = audit()
    motor = json.loads((ROOT / 'config/motors.json').read_text(encoding='utf-8'))['profiles'][encoder]
    for side in ('left', 'right'):
        if isinstance(motor[side + '_cpr'], bool) or not isinstance(motor[side + '_cpr'], int) or not 100 <= motor[side + '_cpr'] <= 65535:
            raise ValueError('CPR must be an integer 100..65535 per output shaft revolution')
    folder = ROOT / 'build' / (profile + '_' + encoder + '_m2')
    folder.mkdir(parents=True, exist_ok=True)
    with (ROOT / 'constraints/pins.csv').open(encoding='utf-8-sig') as handle: rows = list(csv.DictReader(handle))
    if len({r['ball'] for r in rows}) != len(rows): raise ValueError('Duplicate physical pin')
    lines = ['// Carrier M2: J_DRV2-23..30 are the eight brushed motor/encoder signals; old M1 is disabled.']
    for r in rows:
        name = r['signal']
        pull = 'UP' if name == 'uart_rx' or '_enc_' in name or name.startswith('imu_i2c_') else 'DOWN' if r['direction'] == 'OUT' else 'NONE'
        lines += [f'IO_LOC "{name}" {r["ball"]};', f'IO_PORT "{name}" IO_TYPE=LVCMOS33 PULL_MODE={pull} BANK_VCCIO=3.3;']
    (folder / 'balance.cst').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    sdc = 'create_clock -name clk50m -period 20.000 [get_ports {clk50m}]\n'
    for pin in ('rx/rx_meta_s0/D', 'core/enc_l/ab_meta_0_s0/D', 'core/enc_l/ab_meta_1_s0/D',
                'core/enc_r/ab_meta_0_s0/D', 'core/enc_r/ab_meta_1_s0/D',
                'imu/reader/bus/scl_sync_0_s0/D', 'imu/reader/bus/sda_sync_0_s0/D',
                'diagnostics/line_meta_0_s0/D', 'diagnostics/line_meta_1_s0/D'):
        sdc += f'set_false_path -to [get_pins {{{pin}}}]\n'
    # There are no internal multicycle paths or datapath-wide exceptions.
    (folder / 'balance.sdc').write_text(sdc, encoding='utf-8')
    top = (ROOT / 'rtl/brushed_balance_top.sv').read_text(encoding='utf-8')
    top = top.replace('DRIVE_ENABLE=0', 'DRIVE_ENABLE=' + str(int(profile == 'drive')))
    top = top.replace('CPR_LEFT=60000,CPR_RIGHT=60000', f'CPR_LEFT={motor["left_cpr"]},CPR_RIGHT={motor["right_cpr"]}')
    generated = folder / 'brushed_balance_top.sv'
    generated.write_text(top, encoding='utf-8')
    sources = sorted(p for p in (ROOT / 'rtl').rglob('*') if p.suffix in ('.v', '.sv') and p.name != 'brushed_balance_top.sv') + [generated, folder / 'balance.cst', folder / 'balance.sdc']
    project = ET.Element('Project')
    ET.SubElement(project, 'Template').text = 'FPGA'
    ET.SubElement(project, 'Version').text = '5'
    ET.SubElement(project, 'Device', name='GW5AT-138B', pn='GW5AT-LV138PG484AC1/I0').text = 'gw5at138b-012'
    files = ET.SubElement(project, 'FileList')
    for p in sources:
        ET.SubElement(files, 'File', path=Path(os.path.relpath(p, folder)).as_posix(),
                      type={'.sv': 'file.verilog', '.v': 'file.verilog', '.cst': 'file.cst', '.sdc': 'file.sdc'}[p.suffix], enable='1')
    ET.ElementTree(project).write(folder / 'balance.gprj', encoding='utf-8', xml_declaration=True)
    tcl = 'set here [file dirname [file normalize [info script]]]\ncd $here\nopen_project balance.gprj\n'
    for key, value in [('top_module', 'brushed_balance_top'), ('verilog_std', 'sysv2017'), ('output_base_name', 'balance'),
                       ('max_fanout', '32'), ('replicate_resources', '1'), ('timing_driven', '1'),
                       ('use_sspi_as_gpio', '1'), ('use_cpu_as_gpio', '1')]:
        tcl += f'set_option -{key} {value}\n'
    (folder / 'build.tcl').write_text(tcl + 'run all\n', encoding='utf-8')
    metadata = dict(profile=profile, encoder=encoder, motor=motor, hardware_tested=False,pin_profile=pin_audit['pin_profile'],
                    source_sha256={p.relative_to(ROOT).as_posix(): sha(p) for p in sources},
                    template_sha256=sha(ROOT / 'rtl/brushed_balance_top.sv'),
                    config_sha256=sha(ROOT / 'config/motors.json'), pins_sha256=sha(ROOT / 'constraints/pins.csv'),
                    pin_reference_sha256=sha(ROOT/'constraints/carrier_drv2_reference.csv'),pin_profile_sha256=sha(ROOT/'constraints/pin_profile.json'))
    (folder / 'prepared.json').write_text(json.dumps(metadata, indent=2, ensure_ascii=False), encoding='utf-8')
    return folder, metadata


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--profile', choices=('observe', 'drive'), default='observe')
    parser.add_argument('--encoder', choices=('p30_gmr', 'p30_hall'), default='p30_gmr')
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--verify-only', action='store_true', help='Recheck an existing build and its exact source hashes, without rerunning EDA')
    args = parser.parse_args()
    if args.verify_only:
        folder = ROOT / 'build' / (args.profile + '_' + args.encoder + '_m2')
        metadata = json.loads((folder / 'prepared.json').read_text(encoding='utf-8'))
        previous = json.loads((folder / 'result.json').read_text(encoding='utf-8'))
        exit_code = previous['exit_code']
        attempt = folder / ('audit_' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
        attempt.mkdir()
    else:
        folder, metadata = prepare(args.profile, args.encoder)
    if args.prepare_only:
        print(folder / 'balance.gprj'); return
    if not args.verify_only and os.name == 'nt':
        active = subprocess.run(['powershell', '-NoProfile', '-Command', 'Get-Process gw_sh,gw_syn,gw_pnr -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id'], capture_output=True, text=True)
        if active.stdout.strip(): raise SystemExit('Another Gowin build is running; it was left untouched.')
    exe = Path(os.environ.get('GOWIN_HOME', 'C:/Gowin/Gowin_V1.9.12.04_x64')) / 'IDE/bin/gw_sh.exe'
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    if not args.verify_only:
        attempt = folder / ('attempt_' + stamp)
        attempt.mkdir()
        with (attempt / 'build.log').open('w', encoding='utf-8') as log:
            result = subprocess.run([str(exe), str(folder / 'build.tcl')], cwd=folder, stdout=log, stderr=subprocess.STDOUT)
        exit_code = result.returncode
    report = dict(metadata, utc=stamp, exit_code=exit_code, tool=str(exe), programmed=False, verification_only=args.verify_only)
    report['sources_unchanged'] = all(sha(ROOT / p) == h for p, h in metadata['source_sha256'].items())
    report['sources_unchanged'] &= sha(ROOT / 'rtl/brushed_balance_top.sv') == metadata['template_sha256'] and sha(ROOT / 'config/motors.json') == metadata['config_sha256']
    report['sources_unchanged'] &= sha(ROOT / 'constraints/pins.csv') == metadata['pins_sha256']
    report['sources_unchanged'] &= sha(ROOT/'constraints/carrier_drv2_reference.csv')==metadata['pin_reference_sha256'] and sha(ROOT/'constraints/pin_profile.json')==metadata['pin_profile_sha256']
    timing = folder / 'impl/pnr/balance_tr_content.html'
    bit = folder / 'impl/pnr/balance.fs'
    if exit_code == 0 and timing.exists():
        text = timing.read_text(encoding='utf-8', errors='replace')
        report['violations'] = {}
        for kind in ('Setup', 'Hold'):
            match = re.search(r'Numbers of ' + kind + r' Violated Endpoints</td>\s*<td[^>]*>(\d+)', text)
            report['violations'][kind.lower()] = int(match[1]) if match else None
    if exit_code == 0 and bit.exists(): report['bitstream_sha256'] = sha(bit)
    if args.verify_only and report.get('bitstream_sha256') != previous.get('bitstream_sha256'):
        report['sources_unchanged'] = False
    report['passed'] = exit_code == 0 and report.get('violations') == {'setup': 0, 'hold': 0} and report['sources_unchanged'] and 'bitstream_sha256' in report
    if exit_code == 0:
        netlist = folder / 'impl/gwsynthesis/balance.vg'
        text = netlist.read_text(encoding='utf-8', errors='replace') if netlist.exists() else ''
        report['encoder_input_buffers']={name:bool(re.search(r'\bIBUF\s+\S+\s*\(\s*\.O\([^)]*\),\s*\.I\(\s*'+name+r'\s*\)',text)) for name in ('left_enc_a','left_enc_b','right_enc_a','right_enc_b')}
        report['passed'] &= all(report['encoder_input_buffers'].values())
    if args.profile == 'observe' and exit_code == 0:
        outputs = ['left_in1', 'left_in2', 'right_in1', 'right_in2']
        outputs += ['legacy_m1_disable','legacy_m1_cal_disabled']
        outputs += [f'legacy_m1_pwm_disabled[{i}]' for i in range(6)]
        grounded = grounded_outputs(text)
        report['motor_outputs_grounded'] = {p: grounded.get(p, False) for p in outputs}
        report['passed'] &= all(report['motor_outputs_grounded'].values())
    for target in (attempt / 'result.json', folder / 'result.json'):
        target.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k != 'source_sha256'}, ensure_ascii=False, indent=2))
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__': main()
