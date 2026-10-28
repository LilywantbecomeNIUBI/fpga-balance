from pathlib import Path
import json,time,sys
from pd_direction_prepare_20261028 import ROOT,state,action,wait
orientation=sys.argv[1] if len(sys.argv)>1 else 'front';s=state();r=s['record'];begin=time.time();pulse=None;issued=False;outcome='not_started';reason=''
# The old attitude reference is still calibrated after Stop. Rebase at held pose,
# translating target trim by the same offset, preserving the original upright target.
old_trim=int.from_bytes(bytes.fromhex(r['config_hex'])[16:18],'little',signed=True)/100
error=r['pitch']-old_trim;cfg=json.loads((ROOT/'balance/presets/06_PD_direction_check_150mA_500ms.json').read_text())['config'];cfg['trim_deg']=round(-error,2)
try:
 assert s['fresh'] and not s['demo'] and r['attitude_calibrated'],'old attitude reference not available'
 assert r['commissioned_mask']==3 and not any(r[k] for k in ('active','armed','running','commissioning')),'not stopped/calibrated'
 assert r['motor_faults'] in (0,1) and r['stop_reason'] in (0,1),'not just manual Stop'
 assert .4<error<2.8 if orientation=='front' else -2.8<error<-.4,'held tilt outside required signed0.4..2.8deg: '+str(error)
 old=r['time_us'];action('clear');issued=True;deadline=time.monotonic()+2
 while True:
  z=state();q=z['record'];assert z['fresh'],'stale'
  if q['time_us']!=old and q['motor_faults']==q['stop_reason']==0:break
  assert time.monotonic()<deadline,'clear timeout';time.sleep(.02)
 action('config',cfg);wait(lambda s,r:s['config_ack'],2,False)
 action('attitude_zero');wait(lambda s,r:r['attitude_calibrated'] and not r['attitude_calibrating'],6,minimum=.15)
 action('current_zero');q=wait(lambda s,r:r['current_calibrated'] and not r['current_calibrating'],3,minimum=.15)
 assert abs(q['pitch'])<.3,'held pose changed during calibration'
 action('arm');wait(lambda s,r:r['armed'],.7);pulse=time.time();action('start');wait(lambda s,r:r['active'] or r['running'],.5)
 wait(lambda s,r:not r['active'] and not r['running'] and not r['armed'],1.5)
 outcome='completed';reason='single reference-preserving PD direction pulse complete'
except Exception as e:
 reason=str(e)
 if issued:
  try:action('stop')
  except Exception:pass
end=time.monotonic()+.2
while time.monotonic()<end:state();time.sleep(.02)
rows=[];folder=Path(s['log_dir'])
for l in (folder/'events.jsonl').open(encoding='utf-8'):
 a=json.loads(l)
 if a.get('event')=='sample' and a.get('host_time',0)>=(pulse or begin):rows.append(a)
active=[a for a in rows if a['active']]
result={'orientation':orientation,'outcome':outcome,'reason':reason,'physical_error_from_original_upright_deg':error,'previous_trim_deg':old_trim,'compensated_config':cfg,'pulse_wall_time':pulse,'active_samples':len(active),'active_span_ms':((active[-1]['time_us']-active[0]['time_us'])&0xffffffff)/1000 if active else 0,'encoder_net_deg':[sum(((b['angles'][i]-a['angles'][i]+8192)&16383)-8192 for a,b in zip(active,active[1:]))*360/16384 for i in (0,1)],'iq_ranges':[[min(a[k] for a in active),max(a[k] for a in active)] for k in ('iq1_a','iq2_a')] if active else [],'user_visual_observation':'pending','samples':rows}
p=folder/('pd_'+orientation+'_referenced_'+time.strftime('%Y%m%d_%H%M%S')+'.json');p.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps({k:v for k,v in result.items() if k!='samples'}));print('SAVED',p)
