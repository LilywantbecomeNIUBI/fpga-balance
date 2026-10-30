"""Authorized SRAM-only deployment after motor 12 V was disconnected.

No calibration, arm or start commands. Refuse stale/changed/failed build.
"""
from pathlib import Path
import hashlib,json,re,shutil,subprocess,time,urllib.request

ROOT=Path(__file__).resolve().parents[2]
BASE='http://127.0.0.1:18866'

def state():
    return json.load(urllib.request.urlopen(BASE+'/api/state',timeout=3))

def main():
    build=ROOT/'balance/build/drive'
    report=json.loads((build/'result.json').read_text())
    assert report['success'] and report['download_allowed']
    assert report['critical_warnings']==[], 'critical synthesis warnings'
    assert report['bitstream_sha256']!='b6797f56a047f934431a26b86bf8bded413ffd5f6de347e509412e329b0e0974', 'withdrawn image'
    assert report['setup_violations']==report['hold_violations']==0
    for name,digest in report['source_sha256'].items():
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,name
    original=build/'impl/pnr/motor_selftest.fs'
    assert hashlib.sha256(original.read_bytes()).hexdigest()==report['bitstream_sha256']
    assert 'physical_motor_mask' in (build/'balance_top.v').read_text()
    folder=ROOT/'hardware/candidates/axis_isolation_20261028_v2'
    folder.mkdir(parents=True,exist_ok=True)
    bit=folder/'axis_isolation_diagnostic.fs'
    shutil.copyfile(original,bit)
    (folder/'build.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    page=urllib.request.urlopen(BASE,timeout=3).read().decode()
    token=re.search("const token='([^']+)'",page).group(1)
    def post(path,body):
        req=urllib.request.Request(BASE+path,data=json.dumps(body).encode(),headers={
            'Content-Type':'application/json','X-Balance-Token':token,'Origin':BASE})
        return json.load(urllib.request.urlopen(req,timeout=3))
    before=state()
    r=before.get('record')
    if r:
        assert not any(r[k] for k in ('active','armed','running','commissioning','current_calibrating','attitude_calibrating'))
    post('/api/action',{'name':'disconnect'})
    runtime=json.loads((ROOT/'releases/MOTOR_MANUAL_20261028_R4/runtime.json').read_text())
    command=[runtime['programmer'],'--cable-index','1','--location','290','--device','GW5AT-138B',
             '--operation_index','2','--fsFile',str(bit)]
    log=folder/'programmer.log'
    print('Programming SRAM; motor 12V remains OFF; SHA256 '+report['bitstream_sha256'],flush=True)
    with log.open('w',encoding='utf-8') as stream:
        result=subprocess.run(command,stdout=stream,stderr=subprocess.STDOUT,timeout=90)
    assert result.returncode==0 and 'Finished.' in log.read_text(encoding='utf-8',errors='replace'), 'programmer did not confirm completion'
    post('/api/connect',{'port':'COM20'})
    end=time.monotonic()+10
    after=None
    while time.monotonic()<end:
        after=state();r=after.get('record')
        if after['fresh'] and r:break
        time.sleep(.05)
    assert after and after['fresh'] and not after['demo'] and r['drive']
    assert not any(r[k] for k in ('active','armed','running','commissioning','current_calibrating','attitude_calibrating'))
    assert r['commissioned_mask']==0 and not r['current_calibrated'] and not r['attitude_calibrated']
    assert r['motor_faults'] in (0,1) and r['stop_reason'] in (0,1)
    record=dict(bitstream_sha256=report['bitstream_sha256'],sram_programmed=True,flash_programmed=False,
                user_confirmed_motor_12v_off=True,programmer_exit=result.returncode,
                calibration_or_runtime_commands_sent=False,before=before.get('record'),after=r,
                note='Only source/simulation/programmer checks completed; physical motor isolation not yet tested. R4 menu still contains its older firmware.')
    (ROOT/'evidence/engineering/axis_isolation_deployment_20261028_v2.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:r[k] for k in ('active','armed','running','commissioned_mask','current_calibrated','attitude_calibrated','motor_faults','stop_reason')}),flush=True)
    print('SRAM deployment and stopped telemetry verified; no motor test performed.',flush=True)

if __name__=='__main__':main()
