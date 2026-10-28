from pathlib import Path
import json,re,time,urllib.request,urllib.error
ROOT=Path(__file__).resolve().parents[2];B='http://127.0.0.1:18866';token=re.search("const token='([^']+)'",urllib.request.urlopen(B,timeout=2).read().decode()).group(1)
def state():return json.load(urllib.request.urlopen(B+'/api/state',timeout=2))
cmd=[]
def action(n,c=None):
 d={'name':n}
 if c is not None:d['config']=c
 req=urllib.request.Request(B+'/api/action',data=json.dumps(d).encode(),headers={'Content-Type':'application/json','X-Balance-Token':token,'Origin':B})
 try:json.load(urllib.request.urlopen(req,timeout=2))
 except urllib.error.HTTPError as e:raise RuntimeError(e.read().decode())
 cmd.append(n);print(n,flush=True)
def wait(pred,timeout,ack=True,minimum=0):
 begin=time.monotonic()
 while True:
  s=state();r=s['record'];assert s['fresh'] and not s['demo'],'stale/demo';assert not r['motor_faults'] and not r['stop_reason'] and not r['commission_failed'],'FPGA fault';assert not ack or s['config_ack'],'config lost'
  if time.monotonic()-begin>=minimum and pred(s,r):return r
  assert time.monotonic()-begin<timeout,'timeout';time.sleep(.02)
s=state();folder=Path(s['log_dir']);begin=time.time();pulse=None;before=s['record'];outcome='preparation_stopped';reason=''
cfg=json.loads((ROOT/'balance/presets/05_M2_positive_direction_200mA_200ms.json').read_text());cfg.update(test_axis=1,current_target_ma=150,current_ma=200,duration_ms=2000,m1_reverse=False,m2_reverse=False)
try:
 assert s['fresh'] and not s['demo'] and before['commissioned_mask']==3,'both calibration results required'
 assert not any(before[k] for k in ('active','armed','running','commissioning','current_calibrating')),'not stopped'
 assert before['motor_faults'] in (0,1) and before['stop_reason'] in (0,1),'not only manual Stop'
 action('clear');deadline=time.monotonic()+2
 while True:
  z=state();r=z['record'];assert z['fresh'],'stale during clear'
  if r['time_us']!=before['time_us'] and not r['motor_faults'] and not r['stop_reason'] and not r['commission_failed']:
   assert r['commissioned_mask']==3,'electrical calibration lost';break
  assert time.monotonic()<deadline,'clear acknowledgement timeout';time.sleep(.02)
 action('config',cfg);wait(lambda s,r:s['config_ack'],2,False)
 action('attitude_zero');wait(lambda s,r:r['attitude_calibrated'] and not r['attitude_calibrating'],6,minimum=.15)
 action('current_zero');wait(lambda s,r:r['current_calibrated'] and not r['current_calibrating'],3,minimum=.15)
 action('arm');baseline=wait(lambda s,r:r['armed'],.7);pulse=time.time();action('start');wait(lambda s,r:r['active'] or r['running'],.7)
 wait(lambda s,r:not r['active'] and not r['running'] and not r['armed'],3.5)
 outcome='completed';reason='M1 raw +0.15A/2s complete, no recommissioning'
except Exception as e:
 reason=str(e)
 if cmd:
  try:action('stop')
  except Exception:pass
end=time.monotonic()+.3
while time.monotonic()<end:state();time.sleep(.02)
rows=[]
for line in (folder/'events.jsonl').open(encoding='utf-8'):
 r=json.loads(line)
 if r.get('event')=='sample' and r.get('host_time',0)>=(pulse or begin):rows.append(r)
active=[r for r in rows if r['active']];net=[0,0]
for a,b in zip(active,active[1:]):
 for i in (0,1):net[i]+=((b['angles'][i]-a['angles'][i]+8192)&16383)-8192
result=dict(outcome=outcome,reason=reason,commands=cmd,config=cfg,started_wall_time=begin,pulse_wall_time=pulse,active_samples=len(active),active_span_ms=((active[-1]['time_us']-active[0]['time_us'])&0xffffffff)/1000 if active else 0,active_encoder_net_deg=[v*360/16384 for v in net],iq_range_a=[[min(r[k] for r in rows),max(r[k] for r in rows)] for k in ('iq1_a','iq2_a')] if rows else [],before_learned=before.get('m2_diagnostic'),last=rows[-1] if rows else None,samples=rows,user_visual_direction='pending')
p=folder/('m1_positive_150ma_2s_'+time.strftime('%Y%m%d_%H%M%S')+'.json');p.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps({k:v for k,v in result.items() if k not in ('samples','last','before_learned')}));print('SAVED',p)
