"""Authorized M2 +/-100 mA, 200 ms probe after isolation fix; never recommission or retry."""
import json, math
import time
from pathlib import Path
from statistics import mean
from pd_direction_prepare_20261028 import ROOT, state, action, wait


def coast(timeout=25):
    start = time.monotonic()
    stable = None
    previous = None
    while time.monotonic() - start < timeout:
        s = state()
        r = s['record']
        assert s['fresh'] and not s['demo'], 'stale/demo during coast'
        assert not r['motor_faults'] and not r['stop_reason'], 'fault during coast'
        assert not any(r[k] for k in ('active', 'running', 'armed')), 'unexpected run'
        now = time.monotonic()
        if previous is None:
            previous = (now, r['angles'][1])
        elif now - previous[0] >= .25:
            delta = ((r['angles'][1] - previous[1] + 8192) & 16383) - 8192
            if abs(delta) <= 8 and abs(r['wheel_rpm'][1]) < 3:
                stable = now if stable is None else stable
                if now - stable >= .75:
                    return
            else:
                stable = None
            previous = (now, r['angles'][1])
        time.sleep(.02)
    raise RuntimeError('wheel did not coast to rest; no reverse test issued')


def summarize(rows):
    active = [r for r in rows if r['active']]
    diag = [r['m2_diagnostic'] for r in active if r.get('m2_diagnostic', {}).get('running')]
    valid = [d for d in diag if d['park_valid'] and not d['overrun']]
    tail = valid[-100:]
    net = [sum(((b['angles'][i] - a['angles'][i] + 8192) & 16383) - 8192
               for a, b in zip(active, active[1:])) for i in (0, 1)]
    return dict(active_samples=len(active), valid_dq_samples=len(valid),
                trace_unique_sequences=len({d['sequence'] for d in diag}),
                overrun_samples=sum(d['overrun'] for d in diag),
                active_span_ms=((active[-1]['time_us'] - active[0]['time_us']) & 0xffffffff)/1000 if active else 0,
                encoder_net_deg=[n*360/16384 for n in net],
                tail_samples=len(tail),
                tail_mean={k: mean(d[k] for d in tail) for k in ('id_ref_a','iq_ref_a','id_a','iq_a','ud','uq')} if tail else {},
                tail_uq_saturated_fraction=mean(abs(d['uq']) >= .749 for d in tail) if tail else None,
                tail_ud_saturated_fraction=mean(abs(d['ud']) >= .1249 for d in tail) if tail else None)


if __name__ == '__main__':
    s = state()
    before = s['record']
    folder = Path(s['log_dir'])
    events = folder/'events.jsonl'
    result = dict(started_wall_time=time.time(), before=before, runs=[],
                  shared_current_zero=True, electrical_recommissioned=False, outcome='not_started')
    path = ROOT/'evidence/engineering'/('m2_current_probe_'+time.strftime('%Y%m%d_%H%M%S')+'.json')
    issued = False
    try:
        assert s['fresh'] and not s['demo'] and before['commissioned_mask'] == 3, 'not fresh/commissioned'
        assert not any(before[k] for k in ('active','armed','running','commissioning','current_calibrating')), 'not stopped'
        assert before['motor_faults'] in (0,1) and before['stop_reason'] in (0,1), 'not only manual Stop'
        action('clear')
        issued = True
        deadline = time.monotonic()+2
        while True:
            s = state(); r = s['record']
            assert s['fresh'], 'stale during clear'
            if r['time_us'] != before['time_us'] and r['motor_faults'] == r['stop_reason'] == 0:
                break
            assert time.monotonic() < deadline, 'clear timeout'
            time.sleep(.02)
        assert r['commissioned_mask'] == 3, 'electrical calibration lost'
        base = json.loads((ROOT/'balance/presets/05_M2_positive_direction_200mA_200ms.json').read_text())
        base.update(current_ma=150, duration_ms=200, trim_deg=0.0, foc_kp=300, foc_ki=16)
        for index, target in enumerate((100,-100)):
            coast()
            cfg = dict(base, current_target_ma=target)
            action('config', cfg)
            wait(lambda s,r:s['config_ack'],2,False)
            action('attitude_zero')
            wait(lambda s,r:r['attitude_calibrated'] and not r['attitude_calibrating'],6,minimum=.15)
            if index == 0:
                action('current_zero')
                wait(lambda s,r:r['current_calibrated'] and not r['current_calibrating'],3,minimum=.15)
            else:
                assert state()['record']['current_calibrated'], 'shared current zero lost'
            with events.open('rb') as stream:
                stream.seek(0,2); offset=stream.tell()
            action('arm'); wait(lambda s,r:r['armed'],.7)
            pulse = time.time()
            action('start'); wait(lambda s,r:r['active'] or r['running'],.7)
            wait(lambda s,r:not any(r[k] for k in ('active','running','armed')),3.5)
            # Keep host heartbeat alive while the logger flushes the final samples.
            until = time.monotonic()+.15
            while time.monotonic() < until:
                state(); time.sleep(.02)
            with events.open('rb') as stream:
                stream.seek(offset)
                rows=[json.loads(line) for line in stream if line.endswith(b'\n')]
            rows=[r for r in rows if r.get('event') == 'sample' and r.get('host_time',0) >= pulse]
            run=dict(config=cfg,pulse_wall_time=pulse,summary=summarize(rows),samples=rows)
            result['runs'].append(run)
            path.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
            ds=[r['m2_diagnostic'] for r in rows if r['active'] and r.get('m2_diagnostic',{}).get('running') and r['m2_diagnostic']['park_valid']]
            assert ds, 'no valid M2 current trace'
            peak=max(abs(v) for d in ds for v in d['currents_a'])
            run['summary']['sampled_phase_peak_a']=peak
            run['summary']['last10_mean']={k:mean(d[k] for d in ds[-10:]) for k in ('id_a','iq_a','ud','uq')}
            errors=[]
            for d in ds:
                a,b,c=d['currents_a'];beta=(a+2*b)/math.sqrt(3);theta=d['theta']*2*math.pi/65536
                errors.append(max(abs(a*math.cos(theta)+beta*math.sin(theta)-d['id_a']),abs(-a*math.sin(theta)+beta*math.cos(theta)-d['iq_a'])))
            run['summary']['park_recompute_max_error_a']=max(errors)
            path.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
            print(json.dumps(dict(target_ma=target,**run['summary'])),flush=True)
            assert peak<.75, 'sampled phase current abnormal; no further pulse'
            assert max(errors)<.01 and not run['summary']['overrun_samples'], 'invalid current trace; no further pulse'
            assert abs(run['summary']['encoder_net_deg'][0])<.5, 'unselected M1 moved; no further pulse'
            assert abs(run['summary']['last10_mean']['id_a'])<.2, 'excessive Id; no further pulse'
        coast()
        result['outcome']='completed'
    except Exception as e:
        result['outcome']='stopped_on_error'
        result['error']=str(e)
        print('ERROR',str(e),flush=True)
    finally:
        if issued:
            action('stop')
        result['last']=state()['record']
        path.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print('SAVED',path,flush=True)
