"""User-authorized single M2 direction trial; no automatic retries."""
from pathlib import Path
import hashlib,json,re,time,urllib.request,urllib.error
ROOT=Path(__file__).resolve().parents[2]
B='http://127.0.0.1:18866'
page=urllib.request.urlopen(B,timeout=2).read().decode()
token=re.search("const token='([^']+)'",page).group(1)
def state():return json.load(urllib.request.urlopen(B+'/api/state',timeout=2))
commands=[]
def act(name,config=None):
    data={'name':name}
    if config is not None:data['config']=config
    req=urllib.request.Request(B+'/api/action',data=json.dumps(data).encode(),headers={'Content-Type':'application/json','X-Balance-Token':token,'Origin':B})
    try:json.load(urllib.request.urlopen(req,timeout=2))
    except urllib.error.HTTPError as e:raise RuntimeError(e.read().decode())
    commands.append(name);print(name,flush=True)
def check(s,ack=True):
    r=s['record']
    assert s['fresh'] and not s['demo'],'telemetry stale/demo'
    assert r['drive'] and r['independent_commission'] and r['preserve_commission_on_clear'],'firmware identity'
    assert not r['motor_faults'] and not r['stop_reason'] and not r['commission_failed'],'FPGA fault or commissioning failure'
    assert not ack or s['config_ack'],'configuration acknowledgement lost'
    return r
def wait(pred,seconds,ack=True,minimum=0):
    start=time.monotonic()
    while True:
        s=state();r=check(s,ack)
        if time.monotonic()-start>=minimum and pred(s,r):return r
        assert time.monotonic()-start<seconds,'operation timeout'
        time.sleep(.02)
def zero():
    act('current_zero')
    return wait(lambda s,r:r['current_calibrated'] and not r['current_calibrating'],4,minimum=.3)
s=state();folder=Path(s['log_dir']);begin=time.time();pulse=None;stages=[];outcome='preparation_stopped';reason='';stop_sent=False
cfg=json.loads((ROOT/'balance/presets/05_M2_positive_direction_200mA_200ms.json').read_text())
cfg.update(current_target_ma=300,current_ma=300,duration_ms=5000)
try:
    build=json.loads((ROOT/'balance/build/drive/result.json').read_text())
    assert build['bitstream_sha256']=='805489cebf2f61b942ba3a02e1bb392cf83f4e3254a8f8226337cbec02e96a0c'
    assert all(hashlib.sha256((ROOT/f).read_bytes()).hexdigest()==h for f,h in build['source_sha256'].items()),'source changed'
    r=s['record'];assert s['fresh'] and not s['demo'],'not connected/fresh'
    assert not any(r[k] for k in ('active','armed','running','commissioning','current_calibrating','attitude_calibrating')),'not stopped'
    assert not r['motor_faults'] and not r['stop_reason'] and r['commissioned_mask']==3,'requires stopped fault-free completed calibration'
    act('config',cfg);wait(lambda s,r:s['config_ack'],2,False)
    act('attitude_zero');wait(lambda s,r:r['attitude_calibrated'] and not r['attitude_calibrating'],6,minimum=.15)
    zero();r=check(state());assert r['commissioned_mask']==3,'missing electrical calibration'
    assert cfg['m2_reverse'] is False and cfg['current_target_ma']==300 and cfg['test_axis']==2 and cfg['duration_ms']==5000
    act('arm');wait(lambda s,r:r['armed'],.8)
    pulse=time.time();act('start');seen=False;end=time.monotonic()+6
    while True:
        r=check(state());seen=seen or r['active'] or r['running']
        assert r['iq1_a']==0,'M1 torque command unexpectedly nonzero'
        assert r['iq2_a']>=0,'M2 current command is negative'
        if seen and not any(r[k] for k in ('active','running','armed')):
            outcome='completed';reason='single M2 positive-current pulse completed without fault';break
        assert time.monotonic()<end,'pulse completion not observed'
        time.sleep(.01)
except Exception as e:
    reason=str(e)
    if commands:
        try:act('stop');stop_sent=True
        except Exception as stop_error:reason+='; stop error: '+str(stop_error)
    outcome='fault_stopped' if pulse else 'preparation_stopped'
# Keep receiving for coast observation; do not send another motion request.
end=time.monotonic()+.5
while time.monotonic()<end:state();time.sleep(.02)
result={'started_wall_time':begin,'pulse_start_wall_time':pulse,'commands':commands,'commission_stages':stages,'config':cfg,'stop_sent':stop_sent,'outcome':outcome,'reason':reason,'mechanical_direction_visually_confirmed':False}
rows=[]
with (folder/'events.jsonl').open(encoding='utf-8') as f:
    for line in f:
        row=json.loads(line)
        if row.get('event')=='sample' and row.get('host_time',0)>=(pulse or begin):rows.append(row)
if rows:
    keys=('time_us','active','armed','running','commissioned_mask','motor_faults','stop_reason','angles','iq1_a','iq2_a','pitch')
    result['last']={k:rows[-1][k] for k in keys}
    result['first_fault']=next(({k:r[k] for k in keys} for r in rows if r['motor_faults'] or r['stop_reason']),None)
    result['phase_peak_a']=[max(abs(r['currents_a'][i]) for r in rows) for i in range(6)]
    result['iq_command_range_a']=[[min(r[k] for r in rows),max(r[k] for r in rows)] for k in ('iq1_a','iq2_a')]
    result['encoder_unwrapped_net_deg_including_coast']=[sum(((b['angles'][i]-a['angles'][i]+8192)&16383)-8192 for a,b in zip(rows,rows[1:]))*360/16384 for i in range(2)]
    result['active_sample_count']=sum(bool(r['active']) for r in rows)
    active=[r for r in rows if r['active']]
    if active:result['active_sample_span_ms']=((active[-1]['time_us']-active[0]['time_us'])&0xffffffff)/1000
    result['samples']=[{k:r[k] for k in keys} for r in rows]
out=folder/('m2_positive_300ma_5000ms_'+time.strftime('%Y%m%d_%H%M%S')+'.json');out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='samples'},ensure_ascii=True));print('SAVED '+str(out),flush=True)
