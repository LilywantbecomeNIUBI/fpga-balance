from pathlib import Path
import json,time,sys
from pd_direction_prepare_20261028 import ROOT,state,action,wait
s=state();r=s['record'];begin=time.time();pulse=None;issued=False;outcome='not_started';reason='';orientation=sys.argv[1] if len(sys.argv)>1 else 'front'
try:
 assert s['fresh'] and not s['demo'] and s['config_ack'],'not prepared'
 assert not any(r[k] for k in ('active','armed','running','commissioning')),'not stopped'
 assert r['commissioned_mask']==3 and not r['motor_faults'] and not r['stop_reason'],'fault/calibration state'
 if orientation=='front':assert .4<r['pitch']<2.8,'front tilt must be +0.4..+2.8deg; measured '+str(r['pitch'])
 else:assert -2.8<r['pitch']<-.4,'rear tilt must be -2.8..-0.4deg; measured '+str(r['pitch'])
 action('arm');issued=True;wait(lambda s,r:r['armed'],.7)
 pulse=time.time();action('start');wait(lambda s,r:r['active'] or r['running'],.5)
 wait(lambda s,r:not r['active'] and not r['running'] and not r['armed'],1.5)
 outcome='completed';reason='single PD direction pulse completed, no fault'
except Exception as e:
 reason=str(e)
 if issued:
  try:action('stop')
  except Exception:pass
end=time.monotonic()+.2
while time.monotonic()<end:state();time.sleep(.02)
folder=Path(s['log_dir']);rows=[]
for l in (folder/'events.jsonl').open(encoding='utf-8'):
 a=json.loads(l)
 if a.get('event')=='sample' and a.get('host_time',0)>=(pulse or begin):rows.append(a)
active=[a for a in rows if a['active']]
net=[sum(((b['angles'][i]-a['angles'][i]+8192)&16383)-8192 for a,b in zip(active,active[1:]))*360/16384 for i in (0,1)]
result={'orientation':orientation,'initial_pitch':r['pitch'],'outcome':outcome,'reason':reason,'pulse_wall_time':pulse,'active_samples':len(active),'active_encoder_net_deg':net,'iq_ranges':[[min(a[k] for a in active),max(a[k] for a in active)] for k in ('iq1_a','iq2_a')] if active else [],'pitch_range':[min(a['pitch'] for a in active),max(a['pitch'] for a in active)] if active else [],'samples':rows,'user_visual_observation':'pending'}
p=folder/('pd_'+orientation+'_'+time.strftime('%Y%m%d_%H%M%S')+'.json');p.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps({k:v for k,v in result.items() if k!='samples'}));print('SAVED',p)
