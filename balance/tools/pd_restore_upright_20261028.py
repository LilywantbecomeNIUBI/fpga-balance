from pathlib import Path
import json,re,time,urllib.request,urllib.error
ROOT=Path(__file__).resolve().parents[2];B='http://127.0.0.1:18866';token=re.search("const token='([^']+)'",urllib.request.urlopen(B,timeout=2).read().decode()).group(1)
def state():return json.load(urllib.request.urlopen(B+'/api/state',timeout=2))
def action(n,c=None):
 d={'name':n}
 if c is not None:d['config']=c
 req=urllib.request.Request(B+'/api/action',data=json.dumps(d).encode(),headers={'Content-Type':'application/json','X-Balance-Token':token,'Origin':B})
 try:json.load(urllib.request.urlopen(req,timeout=2))
 except urllib.error.HTTPError as e:raise RuntimeError(e.read().decode())
 print(n,flush=True)
def wait(pred,timeout,ack=True,minimum=0):
 start=time.monotonic()
 while True:
  s=state();r=s['record'];assert s['fresh'] and not s['demo'],'stale/demo'
  assert not r['motor_faults'] and not r['stop_reason'] and not r['commission_failed'],'FPGA fault'
  assert not ack or s['config_ack'],'configuration lost'
  if time.monotonic()-start>=minimum and pred(s,r):return r
  assert time.monotonic()-start<timeout,'timeout';time.sleep(.02)
if __name__=='__main__':
 s=state();r=s['record'];assert s['fresh'] and not s['demo'] and r['commissioned_mask']==3,'missing current dual calibration'
 assert not any(r[k] for k in ('active','armed','running','commissioning','current_calibrating')),'not stopped'
 assert r['motor_faults'] in (0,1) and r['stop_reason'] in (0,1),'not just manual Stop'
 action('clear');end=time.monotonic()+2;old=r['time_us']
 while True:
  s=state();r=s['record'];assert s['fresh'],'stale'
  if r['time_us']!=old and not r['motor_faults'] and not r['stop_reason']:break
  assert time.monotonic()<end,'clear timeout';time.sleep(.02)
 assert r['commissioned_mask']==3,'calibration lost'
 cfg=json.loads((ROOT/'balance/presets/07_PD_verified_direction_150mA_2s.json').read_text())['config']
 action('config',cfg);wait(lambda s,r:s['config_ack'],2,False)
 action('attitude_zero');wait(lambda s,r:r['attitude_calibrated'] and not r['attitude_calibrating'],6,minimum=.15)
 action('current_zero');r=wait(lambda s,r:r['current_calibrated'] and not r['current_calibrating'],3,minimum=.15)
 print(json.dumps({k:r[k] for k in ('pitch','rate','active','armed','running','commissioned_mask','motor_faults','stop_reason','gates')}))
 (ROOT/'evidence/engineering/pd_upright_restored_20261028.json').write_text(json.dumps({'config':cfg,'record':r,'log_dir':s['log_dir'],'motion_started':False},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
