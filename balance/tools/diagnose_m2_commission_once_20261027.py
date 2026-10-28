"""One user-authorized M2 commissioning observation; never arms runtime."""
from pathlib import Path
import json,re,time,hashlib,urllib.request,urllib.error
ROOT=Path(__file__).resolve().parents[2];B='http://127.0.0.1:18866'
token=re.search("const token='([^']+)'",urllib.request.urlopen(B,timeout=2).read().decode()).group(1)
def state():return json.load(urllib.request.urlopen(B+'/api/state',timeout=2))
commands=[]
def act(n,c=None):
 d={'name':n}
 if c is not None:d['config']=c
 q=urllib.request.Request(B+'/api/action',data=json.dumps(d).encode(),headers={'Content-Type':'application/json','X-Balance-Token':token,'Origin':B})
 try:json.load(urllib.request.urlopen(q,timeout=2))
 except urllib.error.HTTPError as e:raise RuntimeError(e.read().decode())
 commands.append(n);print(n,flush=True)
def wait(pred,seconds,ack=True,minimum=0):
 start=time.monotonic()
 while True:
  s=state();r=s['record'];assert s['fresh'] and not s['demo'],'stale/demo'
  assert not r['motor_faults'] and not r['stop_reason'] and not r['commission_failed'],'FPGA fault/commission failed'
  assert not ack or s['config_ack'],'configuration acknowledgement lost'
  if time.monotonic()-start>=minimum and pred(s,r):return r
  assert time.monotonic()-start<seconds,'operation timeout'
  time.sleep(.02)
s=state();begin=time.time();folder=Path(s['log_dir']);outcome='preparation_stopped';reason='';stop_sent=False;commission_start=None
cfg=json.loads((ROOT/'balance/presets/05_M2_positive_direction_200mA_200ms.json').read_text());cfg.update(current_target_ma=0,current_ma=300)
try:
 b=json.loads((ROOT/'balance/build/drive/result.json').read_text());assert b['bitstream_sha256']=='6c71a09d55e70f278801772dec404123363f170aed88194bd1e8faeffb6bdba6'
 assert all(hashlib.sha256((ROOT/f).read_bytes()).hexdigest()==h for f,h in b['source_sha256'].items()),'source hash drift'
 r=s['record'];d=r.get('m2_diagnostic');assert s['fresh'] and not s['demo'] and d and d['selected_motor']==2,'missing M2 diagnostic identity'
 assert not any(r[k] for k in ('active','armed','running','commissioning','current_calibrating')),'not stopped'
 old=r['time_us'];act('clear');end=time.monotonic()+2
 while True:
  s=state();r=s['record'];assert s['fresh'],'stale during clear'
  if r['time_us']!=old and not r['motor_faults'] and not r['stop_reason'] and not r['commission_failed']:break
  assert time.monotonic()<end,'clear acknowledgement timeout'
  time.sleep(.02)
 act('config',cfg);wait(lambda s,r:s['config_ack'],2,False)
 act('current_zero');r=wait(lambda s,r:r['current_calibrated'] and not r['current_calibrating'],4,minimum=.3)
 seq=r['m2_diagnostic']['sequence']
 wait(lambda s,r:r['m2_diagnostic']['sequence']!=seq and r['m2_diagnostic']['park_valid'],1)
 commission_start=time.time();act('commission_m2')
 r=wait(lambda s,r:r['commissioned_mask']==2 and not r['commissioning'],5,minimum=.2)
 assert r['commission_state']==6 and not any(r[k] for k in ('active','armed','running')),'commission did not exit'
 outcome='commission_completed';reason='M2 FSM complete, real DQ observation captured; no runtime command'
except Exception as e:
 reason=str(e)
 if commands:
  try:act('stop');stop_sent=True
  except Exception as e:reason+='; Stop error '+str(e)
 outcome='commission_stopped' if commission_start else 'preparation_stopped'
end=time.monotonic()+.3
while time.monotonic()<end:state();time.sleep(.02)
rows=[]
for l in (folder/'events.jsonl').open(encoding='utf-8'):
 r=json.loads(l)
 if r.get('event')=='sample' and r.get('host_time',0)>=begin:rows.append(r)
result=dict(started_wall_time=begin,commission_start_wall_time=commission_start,commands=commands,config=cfg,outcome=outcome,reason=reason,stop_sent=stop_sent,runtime_started=False,samples=rows)
p=folder/('m2_commission_real_dq_'+time.strftime('%Y%m%d_%H%M%S')+'.json');p.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='samples'}));print('SAVED',p)
if rows:print('LAST',json.dumps({k:rows[-1][k] for k in ('active','armed','running','commissioning','commissioned_mask','motor_faults','stop_reason','m2_diagnostic')}))
