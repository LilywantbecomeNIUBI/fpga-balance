"""Persistent manual test records. This module never sends hardware commands."""
import json
import math
import secrets
import time
from dataclasses import asdict
from statistics import mean
from protocol import Config


def summarize(rows, axis):
    active = [r for r in rows if r['active']]
    net = sum(((b['angles'][axis-1]-a['angles'][axis-1]+8192)&16383)-8192
              for a,b in zip(active,active[1:]))
    ds = [r['m2_diagnostic'] for r in active if axis == 2 and
          r.get('m2_diagnostic',{}).get('selected_motor') == 2 and
          r['m2_diagnostic']['running'] and r['m2_diagnostic']['park_valid'] and
          not r['m2_diagnostic']['overrun']]
    tail = ds[-100:]
    return dict(samples=len(active), span_ms=((active[-1]['time_us']-active[0]['time_us'])&0xffffffff)/1000 if active else 0,
                net_degrees=net*360/16384,
                tail_m2_dq={k:mean(d[k] for d in tail) for k in ('id_ref_a','iq_ref_a','id_a','iq_a','ud','uq')} if tail else None,
                dq_samples=len(ds), tail_samples=len(tail),
                sampled_phase_peak_a=max((abs(v) for r in active for v in r['currents_a'][(axis-1)*3:axis*3]),default=None),
                d_saturated_fraction=mean(abs(d['ud'])>=.1249 for d in tail) if tail else None,
                q_saturated_fraction=mean(abs(d['uq'])>=.749 for d in tail) if tail else None,
                faults=sorted({r['motor_faults'] for r in rows}),
                stop_reasons=sorted({r['stop_reason'] for r in rows}))


class TestStore:
    def __init__(self, folder):
        self.folder=folder
        folder.mkdir(parents=True,exist_ok=True)

    def path(self, identifier):
        if not isinstance(identifier,str) or len(identifier)!=16 or any(c not in '0123456789abcdef' for c in identifier):
            raise ValueError('invalid test id')
        return self.folder/(identifier+'.json')

    def read(self, identifier):
        return json.loads(self.path(identifier).read_text(encoding='utf-8'))

    def recent(self):
        files=sorted(self.folder.glob('*.json'),key=lambda p:p.stat().st_mtime,reverse=True)[:40]
        return [{k:v for k,v in json.loads(p.read_text(encoding='utf-8')).items() if k!='samples'} for p in files]

    def save(self, body, rows, demo, log_dir):
        cfg=Config(**body['config']);cfg.body(0)
        if cfg.mode!=1 or cfg.test_axis not in (1,2):raise ValueError('single-axis current test required')
        start=body['started_wall'];end=body['ended_wall']
        if any(isinstance(v,bool) or not isinstance(v,(float,int)) or not math.isfinite(v) for v in (start,end)) or not 0<=end-start<=30:
            raise ValueError('invalid capture time')
        if start>time.time()+1 or time.time()-end>30:raise ValueError('capture is not recent')
        samples=[r for r in rows if start<=r['host_time']<=end]
        identifier=secrets.token_hex(8)
        result=dict(id=identifier,saved_wall=time.time(),started_wall=start,ended_wall=end,
                    config=asdict(cfg),outcome=str(body.get('outcome','unknown'))[:300],
                    note=str(body.get('note',''))[:300],demo=demo,log_dir=str(log_dir),
                    current_zero_requested=bool(body.get('current_zero_requested',True)),
                    summary=summarize(samples,cfg.test_axis),samples=samples)
        self.path(identifier).write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        return {k:v for k,v in result.items() if k!='samples'}
