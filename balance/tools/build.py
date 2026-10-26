"""Build only. Never downloads or opens serial. Requires clean STA for success."""
from pathlib import Path
import argparse, hashlib, json, re, subprocess, sys, xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'balance'
sys.path.insert(0,str(ROOT/'motor_control/tools'))
from prepare_ip import main as prepare_ip, IDE
from timing import read_timing_reports

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--profile',choices=['observe','drive'],default='observe')
    p.add_argument('--reuse-ip',action='store_true',help='reuse prepared IP; verify installed template provenance')
    a=p.parse_args()
    target=BASE/'build'/a.profile;target.mkdir(parents=True,exist_ok=True)
    report_path=target/'result.json'
    report_path.write_text(json.dumps(dict(success=False,status='building',programmed=False)))
    frozen=json.loads((ROOT/'hardware/reference/frozen_pins.json').read_text(encoding='utf-8'))
    for name,h in frozen['constraints_sha256'].items():
        assert hashlib.sha256((ROOT/'motor_control/constraints'/name).read_bytes()).hexdigest()==h, name
    provenance=json.loads((BASE/'vendor/imu/PROVENANCE.json').read_text(encoding='utf-8'))
    for name,h in provenance['sha256'].items():
        assert hashlib.sha256((BASE/'vendor/imu'/name).read_bytes()).hexdigest()==h, name
    if a.reuse_ip:
        records=json.loads((ROOT/'motor_control/ip/foc_light/SOURCE.json').read_text(encoding='utf-8'))
        for record in records:
            f=ROOT/'motor_control/ip/foc_light'/record['file']
            assert hashlib.sha256(f.read_bytes()).hexdigest()==record['sha256']
    else:prepare_ip()
    top=(BASE/'src/balance_top.v').read_text(encoding='utf-8')
    assert top.count('parameter ALLOW_DRIVE=0')==1
    generated=target/'balance_top.v';generated.write_text(top.replace('parameter ALLOW_DRIVE=0','parameter ALLOW_DRIVE='+str(int(a.profile=='drive'))),encoding='utf-8')
    files=[f for f in sorted((BASE/'src').glob('*.v')) if f.name!='balance_top.v']+[generated]
    files+=sorted((BASE/'vendor/imu').glob('*.v'))+sorted((ROOT/'motor_control/src').glob('*.v'))
    files += [ROOT/'motor_control/ip/foc_light'/n for n in ['foc_current_loop_control_light_wrap.v','foc_current_loop_control_light_encrypt.v']]
    project=ET.Element('Project');ET.SubElement(project,'Template').text='FPGA';ET.SubElement(project,'Version').text='5'
    ET.SubElement(project,'Device',name='GW5AT-138B',pn='GW5AT-LV138PG484AC1/I0').text='gw5at138b-012'
    listing=ET.SubElement(project,'FileList')
    for f in files: ET.SubElement(listing,'File',path=f.as_posix(),type='file.verilog',enable='1')
    for suffix,typ in [('cst','file.cst'),('sdc','file.sdc')]:
        f=ROOT/'motor_control/constraints'/('motor_selftest.'+suffix)
        ET.SubElement(listing,'File',path=f.as_posix(),type=typ,enable='1');files.append(f)
    files += [ROOT/'motor_control/ip/foc_light'/n for n in ['define.vh','parameter.vh','static_macro_define.v']]
    files += [BASE/'src/balance_top.v',BASE/'vendor/imu/PROVENANCE.json',ROOT/'hardware/active_profile.json']
    hashes={str(f.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
    gprj=target/'motor_selftest.gprj';ET.ElementTree(project).write(gprj,encoding='utf-8',xml_declaration=True)
    tcl=target/'build.tcl'
    tcl.write_text('open_project {'+gprj.as_posix()+'}\nset_option -top_module balance_top\nset_option -verilog_std sysv2017\nset_option -output_base_name motor_selftest\nset_option -use_sspi_as_gpio 1\nset_option -use_cpu_as_gpio 1\nrun all\n',encoding='utf-8')
    with (target/'build.log').open('w',encoding='utf-8') as log:
        done=subprocess.run([str(IDE/'bin/gw_sh.exe'),str(tcl)],cwd=ROOT/'motor_control',stdout=log,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,timeout=900)
    content=(target/'build.log').read_text(encoding='utf-8',errors='replace')
    report=dict(success=False,profile=a.profile,gowin_exit=done.returncode,programmed=False,physical_balance_tested=False,
                motor_outputs_permanently_disabled=a.profile=='observe',m2_individual_bench_accepted=True,current_reverse_mask=7,protocol_version=2,
                errors=re.findall(r'^ERROR.*',content,re.M),source_sha256=hashes,
                sources_unchanged=all(hashlib.sha256((ROOT/f).read_bytes()).hexdigest()==h for f,h in hashes.items()))
    try: report.update(read_timing_reports(target/'impl/pnr'))
    except ValueError as exc: report['timing_error']=str(exc)
    bit=target/'impl/pnr/motor_selftest.fs'
    netlist=target/'impl/gwsynthesis/motor_selftest.vg'
    if a.profile=='observe' and netlist.exists():
        text=netlist.read_text(encoding='utf-8',errors='replace')
        pins=[f'm{m}_pwm_{phase}{side}' for m in (1,2) for phase in 'abc' for side in 'hl']
        pins += ['m1_drv_en','m2_drv_en','m1_cal','m2_cal']
        grounded={pin:bool(re.search(r'OBUF\s+'+pin+r'_obuf\s*\(\s*\.O\('+pin+r'\),\s*\.I\(GND\)',text)) for pin in pins}
        report['netlist_motor_pins_grounded']=grounded
        report['netlist_sha256']=hashlib.sha256(netlist.read_bytes()).hexdigest()
    if bit.exists(): report['bitstream_sha256']=hashlib.sha256(bit.read_bytes()).hexdigest()
    report['success']=done.returncode==0 and not report['errors'] and bit.exists() and report['sources_unchanged'] and report.get('setup_violations')==report.get('hold_violations')==0
    if a.profile=='observe':report['success']=report['success'] and all(report.get('netlist_motor_pins_grounded',{}).values()) and len(report.get('netlist_motor_pins_grounded',{}))==16
    report['download_allowed']=report['success']
    report_path.write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k!='source_sha256'},indent=2))
    return 0 if report['success'] else 1

if __name__=='__main__':sys.exit(main())
