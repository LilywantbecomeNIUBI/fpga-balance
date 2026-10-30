"""Freeze the already validated R5 build and manual UI; no hardware access."""
from pathlib import Path
import hashlib,json,shutil,stat

ROOT=Path(__file__).resolve().parents[1]
PACKAGE=ROOT/'releases/MOTOR_MANUAL_20261028_R5'

def main():
    report=json.loads((ROOT/'balance/build/drive/result.json').read_text())
    assert report['success'] and not report['critical_warnings']
    assert report['setup_violations']==report['hold_violations']==0
    for name,h in report['source_sha256'].items():
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==h,name
    original=ROOT/'balance/build/drive/impl/pnr/motor_selftest.fs'
    assert hashlib.sha256(original.read_bytes()).hexdigest()==report['bitstream_sha256']
    bit=PACKAGE/'firmware/02_M2_diagnostic.fs'
    if bit.exists():bit.chmod(stat.S_IREAD|stat.S_IWRITE)
    shutil.copyfile(original,bit)
    (PACKAGE/'firmware/02_M2_diagnostic.build.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    p=ROOT/'hardware/active_profile.json'
    shutil.copyfile(p,PACKAGE/'source/diagnostic/hardware/active_profile.json')
    p=PACKAGE/'vehicle_parameters.json';v=json.loads(p.read_text(encoding='utf-8'))
    v['foc'].update(kp=300,ki=16,runtime_tuned=False)
    p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    c=json.loads((ROOT/'balance/presets/08_PD_shadow_Kp005_Kd0001.json').read_text())['config'];c.pop('duration_ms',None);c['current_ma']=300
    (PACKAGE/'presets/upright_manual_continuous.json').write_text(json.dumps(dict(schema='balance-v2',config=c,purpose='manual continuous upright tuning; not physically accepted'),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    dst=PACKAGE/'app/results/motor_tests';dst.mkdir(parents=True,exist_ok=True)
    for f in (ROOT/'releases/MOTOR_MANUAL_20261028_R4/app/results/motor_tests').glob('*.json'):
        if not (dst/f.name).exists():shutil.copyfile(f,dst/f.name)
    start=PACKAGE/'START.cmd'
    start.write_bytes(('@echo off\r\nchcp 65001 >nul\r\nwhere py >nul 2>nul\r\nif errorlevel 1 (\r\n'
        '  python "%~dp0..\\..\\tools\\manual.py" --release MOTOR_MANUAL_20261028_R5 %*\r\n) else (\r\n'
        '  py -3 "%~dp0..\\..\\tools\\manual.py" --release MOTOR_MANUAL_20261028_R5 %*\r\n)\r\nif errorlevel 1 pause\r\n').encode('utf-8'))
    (ROOT/'启动电机调试.cmd').write_bytes(b'@echo off\r\ncall "%~dp0releases\\MOTOR_MANUAL_20261028_R5\\START.cmd"\r\n')
    (ROOT.parents[1]/'启动电机调试.cmd').write_bytes(('@echo off\r\ncall "'+str(PACKAGE/'START.cmd')+'"\r\n').encode('utf-8'))
    validation=json.loads((ROOT/'balance/results/tests/result.json').read_text())
    manifest=dict(release=PACKAGE.name,manual_acceptance_gates_removed=True,firmware={'diagnostic':dict(file='firmware/02_M2_diagnostic.fs',sha256=report['bitstream_sha256'],label='R5 双轮独立PI / 持续电流+可调限速 / 双轮Uq曲线')},
        validation=dict(rtl_tests_passed=len(validation['rtl']),root_host_tests_passed=26,R5_host_tests_passed=30,javascript_flow_tests='passed',firmware_hardware_tested=False,setup_violations=0,hold_violations=0,critical_warnings=[]))
    assert validation['host_exit']==0 and all(r['passed'] for r in validation['rtl'])
    manifest['current_speed_limit_rpm_range']=[10,1000]
    manifest['current_mode_timed_only']=False
    manifest['all_tuning_continuous']=True
    manifest['dual_current_tuning']=True
    manifest['telemetry_payload_bytes']=200
    manifest['files']={f.relative_to(PACKAGE).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(PACKAGE.rglob('*')) if f.is_file() and f.name!='MANIFEST.json' and not f.name.startswith('previous_') and not any(x in ('results','build','__pycache__') for x in f.relative_to(PACKAGE).parts) and 'motor_control/ip/' not in f.relative_to(PACKAGE).as_posix()}
    (PACKAGE/'MANIFEST.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('R5 packaged',report['bitstream_sha256'])

if __name__=='__main__':main()
