"""Local balance console. Default disconnected; --demo never opens hardware."""
from pathlib import Path
import argparse
from collections import deque
from dataclasses import asdict
import csv
import io
import json
import secrets
import statistics
import sys
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

from protocol import Config, Parser, command, frame, demo_packet, GATES
from motor_tests import TestStore

def stationary_check(rows):
    """Advisory only; current zero is still required by the FPGA."""
    tail=list(rows)[-500:]
    if not tail:return True,'Warning: 尚无静止抽样数据'
    warnings=[]
    for i in range(6):
        values=[r['currents_a'][i] for r in tail]
        if abs(statistics.mean(values))>=.025 or max(abs(v) for v in values)>=.225:
            warnings.append(f'相电流{i+1}静止偏置/峰值超限')
    return True,('Warning: '+'; '.join(warnings)) if warnings else '静止电流抽样正常'



class LocalServer(ThreadingHTTPServer):
    allow_reuse_address = False


class Link:
    def __init__(self, demo=False):
        self.demo = demo
        self.lock = threading.RLock()
        self.serial = None
        self.port = None
        self.parser = Parser()
        self.record = None
        self.last_rx = 0
        self.browser_seen = time.monotonic()
        self.seq = 0
        self.pending_config = None
        self.config_deadline = 0
        self.config_ack = False
        self.message = '模拟数据 · 未连接硬件' if demo else '未连接；连接后先被动识别 Balance V2 固件'
        self.history = deque(maxlen=12000)
        self.queue = deque()
        self.closed = False
        self.stopped_for_timeout = False
        self.needs_initial_stop = False
        stamp = time.strftime('%Y%m%d_%H%M%S')+'_'+secrets.token_hex(3)
        self.folder = ROOT/'results'/stamp
        self.folder.mkdir(parents=True)
        self.raw_log = (self.folder/'rx.bin').open('ab')
        self.log = (self.folder/'events.jsonl').open('a', encoding='utf-8')
        self.event('session', demo=demo, hardware_programmed=False)
        self.thread = threading.Thread(target=self.worker, daemon=True)
        self.thread.start()

    def event(self, kind, **values):
        self.log.write(json.dumps(dict(wall_time=time.time(), event=kind, **values), ensure_ascii=False)+'\n')
        self.log.flush()

    @staticmethod
    def ports():
        import serial.tools.list_ports
        return [dict(port=p.device, description=p.description) for p in serial.tools.list_ports.comports()]

    def fresh(self):
        return self.record is not None and time.monotonic()-self.last_rx < .25

    def next_seq(self):
        self.seq = (self.seq+1)&255
        return self.seq

    def disconnect(self):
        with self.lock:
            if self.serial:
                if self.record is not None:
                    self.serial.write(b'X')
                self.serial.close()
            self.serial = None; self.port = None; self.record = None
            self.config_ack = False; self.pending_config = None; self.queue.clear()

    def connect(self, port):
        if self.demo: raise ValueError('模拟模式不能连接硬件；用正常启动器打开新实例')
        if port not in [p['port'] for p in self.ports()]: raise ValueError('请选择枚举到的串口')
        import serial
        with self.lock:
            self.disconnect()
            # No reset-line toggle and absolutely no TX before protocol identification.
            s = serial.Serial(port=None, baudrate=921600, timeout=0, write_timeout=.1)
            s.dtr = False; s.rts = False; s.port = port; s.open()
            self.serial = s; self.port = port; self.parser = Parser()
            self.stopped_for_timeout = False
            self.needs_initial_stop = True
            self.message = '串口已开，正在被动识别；收到正确 CRC 的 Balance V2 帧前不发送任何字节'
            self.event('connect', port=port)

    def action(self, name, values=None):
        with self.lock:
            if name == 'disconnect': self.disconnect(); return
            if name == 'stop':
                self.config_ack = False; self.pending_config = None; self.queue.clear()
                if self.serial and self.record is not None: self.serial.write(b'X')
                self.message = '已请求停止；清故障后须重新应用参数与校零；电角标定是否保留以固件回报为准'
                self.event('stop', sent=bool(self.serial and self.record is not None)); return
            if self.demo: raise ValueError('模拟模式仅显示曲线，控制按钮不向硬件发送命令')
            if not self.serial or not self.fresh(): raise ValueError('未收到新鲜的 Balance V2 数据，命令已拦截')
            r = self.record
            if name == 'config':
                if r['active'] or r['armed'] or r['commissioning'] or r['current_calibrating'] or r['attitude_calibrating']:
                    raise ValueError('请先停止，等待校准结束后修改参数')
                if r['stop_reason'] or (r['drive'] and r['motor_faults']): raise ValueError('先人工清故障，再应用参数')
                if not r.get('dual_current_tuning'): raise ValueError('双轮独立电流环需要下载新版 FPGA 固件')
                cfg = Config(**(values or {}))
                if cfg.mode==1 and not (r.get('current_speed_limit_supported') and r.get('current_continuous_supported')): raise ValueError('持续电流及可调限速需要下载新版FPGA固件')
                body = cfg.body(self.next_seq())
                self.pending_config = body.hex(); self.config_deadline = time.monotonic()+1
                self.config_ack = False; self.queue.append(frame(body))
                self.event('config_requested', config=asdict(cfg), body=body.hex())
                self.message = '参数已发送，等待 FPGA 完整回显确认'
                return
            commissioning_action = name in ('commission_m1', 'commission_m2')
            if name not in ('clear', 'pause', 'current_zero', 'attitude_zero', 'commission_m1', 'commission_m2', 'arm', 'start'):
                raise ValueError('未知操作')
            if name not in ('clear','pause') and not self.config_ack:
                raise ValueError('参数尚未获得 FPGA 确认')
            if commissioning_action:
                if not r.get('independent_commission'): raise ValueError('当前固件不支持指定电机标定；请先断12V下载新版')
                selected = 1 if name == 'commission_m1' else 2
                if r['commissioned_mask'] & selected and not r.get('preserve_commission_on_clear'): raise ValueError('该电机本次已标定；重新标定须人工清故障并重新校零')
            if commissioning_action or name in ('arm', 'start'):
                if not r['drive']: raise ValueError('观察版物理禁止驱动，请在电机验收后使用驱动版')
                if r['stop_reason'] or r['motor_faults']: raise ValueError('故障锁存中')
                if r['commission_failed']: raise ValueError('电角标定失败；检查硬件后人工清故障，不能直接重试')
                ok,reason=stationary_check(self.history)
                if reason.startswith('Warning:'):
                    print(reason,flush=True);self.event('warning',message=reason)
            if name in ('arm', 'start') and r['gates'] & 0xe1f != 0xe1f:
                raise ValueError('启动条件未全部满足')
            if name == 'start' and not r['armed']: raise ValueError('请先解锁，并在 1 秒内开始单次试运行')
            if name == 'clear': self.config_ack = False; self.pending_config = None
            self.queue.append(command(name, self.next_seq()))
            self.event('command_requested', command=name)
            self.message = f'已发送 {name}；以 FPGA 状态为准'

    def accept(self, records):
        for r in records:
            r['host_time'] = time.time(); r['demo'] = self.demo
            if self.record:
                dt = ((r['time_us']-self.record['time_us'])&0xffffffff)/1e6
                r['rpm'] = [(((a-b+8192)&16383)-8192)*60/16384/dt if 0 < dt < .1 else None
                            for a,b in zip(r['angles'],self.record['angles'])]
            else: r['rpm'] = [None,None]
            r['rpm_raw'] = r['rpm']; r['rpm'] = r['wheel_rpm']
            self.record = r; self.last_rx = time.monotonic()
            self.history.append(r)
            self.log.write(json.dumps(dict(event='sample', **r), ensure_ascii=False)+'\n')
            if self.pending_config and r['configured'] and r['config_hex'] == self.pending_config:
                self.config_ack = True; self.pending_config = None; self.message = 'FPGA 参数回显一致；已有姿态、电流和电角标定保留；需要时手动重新校零'
                self.event('config_ack', body=r['config_hex'])
            if not r['configured'] or r['stop_reason'] or (r['drive'] and r['motor_faults']): self.config_ack = False
            if r['commission_failed']:
                self.message='电角标定失败；驱动已退出。检查硬件后人工清故障，再重新校零与标定'
            elif r['rejected']:
                self.message=f"FPGA 拒绝操作 {r['rejected']}；请核对启动条件与当前状态"

    def worker(self):
        started = last_heartbeat = time.monotonic()
        while not self.closed:
            try:
                with self.lock:
                    now = time.monotonic()
                    if self.demo: self.accept(self.parser.feed(demo_packet(now-started)))
                    elif self.serial:
                        raw = self.serial.read(min(self.serial.in_waiting, 8192))
                        if raw:
                            self.raw_log.write(raw); self.accept(self.parser.feed(raw))
                        browser_ok = now-self.browser_seen < .6
                        healthy = self.fresh() and browser_ok
                        if self.record is not None and self.needs_initial_stop:
                            self.serial.write(b'X'); self.queue.clear(); self.config_ack=False
                            self.pending_config=None; self.needs_initial_stop=False
                            self.message='已识别集成固件并请求停止；先人工清故障，再应用本次参数'
                            self.event('identified_initial_stop')
                        elif self.record is not None and not healthy:
                            if not self.stopped_for_timeout:
                                self.serial.write(b'X'); self.queue.clear(); self.config_ack = False
                                self.pending_config = None; self.stopped_for_timeout = True
                                self.message = '页面或串口超时：已发停止；须人工清故障与重新配置'
                                self.event('timeout_stop', browser_ok=browser_ok)
                        elif healthy:
                            self.stopped_for_timeout = False
                            while self.queue: self.serial.write(self.queue.popleft())
                            if now-last_heartbeat >= .025:
                                self.serial.write(command('heartbeat', self.next_seq())); last_heartbeat = now
                    if self.pending_config and now > self.config_deadline:
                        self.pending_config = None; self.config_ack = False; self.message = '参数确认超时，请检查拒绝码与串口'
                        self.event('config_timeout')
            except Exception as exc:
                with self.lock:
                    self.message = f'通信错误：{exc}'; self.config_ack = False
                    self.event('communication_error', error=str(exc))
                    try: self.disconnect()
                    except Exception: self.serial = None
            time.sleep(.005)

    def snapshot(self, ping=True):
        with self.lock:
            if ping: self.browser_seen = time.monotonic()
            return dict(release_id=ROOT.parent.name,demo=self.demo, connected=self.serial is not None, port=self.port,
                        fresh=self.fresh(), config_ack=self.config_ack, message=self.message,
                        dq_history=[[r['time_us']/1e6,*[(r.get(axis+'_diagnostic') or {}).get(k) for axis in ('m1','m2') for k in ('iq_ref_a','iq_a','id_ref_a','id_a')],*[(r.get(axis+'_diagnostic') or {}).get('uq') for axis in ('m1','m2')],*[(sign*(.25 if (r.get(axis+'_diagnostic') or {}).get('alignment') else .75)) for axis in ('m1','m2') for sign in (1,-1)]] for r in list(self.history)[-600:]],
                        record=self.record, stats=dict(packets=self.parser.packets, crc_errors=self.parser.crc_errors,
                        discarded=self.parser.discarded, gaps=self.parser.gaps), gates=GATES,
                        stationary_preflight=stationary_check(self.history)[1], log_dir=str(self.folder), history=[[r['time_us']/1e6,r['pitch'],r['rate'],r['shadow_a'],
                            *r['rpm'],*r['currents_a']] for r in list(self.history)[-600:]])

    def csv(self):
        with self.lock: rows=list(self.history)
        out=io.StringIO(); writer=csv.writer(out)
        writer.writerow(['host_time','time_us','pitch_deg','rate_dps','shadow_a','iq1_a','iq2_a','rpm1','rpm2',
                         'stop_reason','motor_faults','demo','ia1','ib1','ic1','ia2','ib2','ic2','speed_trim_deg',
                         'm2_sequence','m2_theta','m2_id_ref_a','m2_iq_ref_a','m2_id_a','m2_iq_a','m2_ud','m2_uq','m2_park_valid','m2_overrun','m2_zero','m2_reverse'])
        for r in rows:
            writer.writerow([r[k] for k in ('host_time','time_us','pitch','rate','shadow_a','iq1_a','iq2_a')]+
                            r['rpm']+[r['stop_reason'],r['motor_faults'],r['demo']]+r['currents_a']+[r['speed_trim_deg']]+
                            [(r.get('m2_diagnostic') or {}).get(k) for k in ('sequence','theta','id_ref_a','iq_ref_a','id_a','iq_a','ud','uq','park_valid','overrun')]+
                            [((r.get('m2_diagnostic') or {}).get('learned_zero') or [None,None])[1],bool((r.get('m2_diagnostic') or {}).get('learned_reverse',0)&2) if r.get('m2_diagnostic') else None])
        return out.getvalue().encode('utf-8-sig')

    def close(self):
        self.closed=True; self.thread.join(1)
        with self.lock:
            try: self.disconnect()
            finally: self.log.close(); self.raw_log.close()


def make_handler(link, token, port):
    tests = TestStore(ROOT/'results'/'motor_tests')
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_): pass
        def send(self, status, body, content_type='application/json; charset=utf-8'):
            if not isinstance(body, bytes): body=json.dumps(body, ensure_ascii=False).encode()
            self.send_response(status); self.send_header('Content-Type',content_type)
            self.send_header('Content-Length',str(len(body))); self.send_header('Cache-Control','no-store')
            self.send_header('X-Content-Type-Options','nosniff'); self.end_headers(); self.wfile.write(body)
        def authorized(self):
            return self.headers.get('Host')==f'127.0.0.1:{port}' and self.headers.get('Origin',f'http://127.0.0.1:{port}')==f'http://127.0.0.1:{port}'
        def do_GET(self):
            if not self.authorized(): return self.send(403, {'error':'local origin required'})
            if self.path=='/': return self.send(200,(HERE/'index.html').read_bytes().replace(b'__TOKEN__',token.encode()),'text/html; charset=utf-8')
            if self.path=='/manual_start.js': return self.send(200,(HERE/'manual_start.js').read_bytes(),'application/javascript; charset=utf-8')
            if self.path=='/custom_test.js': return self.send(200,(HERE/'custom_test.js').read_bytes(),'application/javascript; charset=utf-8')
            if self.path=='/api/m2-test-samples':
                with link.lock:
                    samples=[{k:r[k] for k in ('host_time','time_us','angles','active','running','motor_faults','stop_reason')} for r in list(link.history)[-1400:]]
                return self.send(200,{'samples':samples})
            if self.path=='/api/motor-tests': return self.send(200,tests.recent())
            if self.path.startswith('/api/motor-tests/'):
                try:return self.send(200,tests.read(self.path.rsplit('/',1)[1]))
                except (ValueError,FileNotFoundError):return self.send(404,{'error':'test not found'})
            if self.path=='/api/vehicle-parameters': return self.send(200,(HERE.parent.parent/'vehicle_parameters.json').read_bytes())
            if self.path=='/api/state': return self.send(200,link.snapshot())
            if self.path=='/api/ports':
                try: return self.send(200,link.ports())
                except ImportError: return self.send(200,[])
            if self.path=='/export.csv': return self.send(200,link.csv(),'text/csv; charset=utf-8')
            return self.send(404,{'error':'not found'})
        def do_POST(self):
            if not self.authorized() or self.headers.get('X-Balance-Token')!=token: return self.send(403,{'error':'token/origin'})
            try:
                n=int(self.headers.get('Content-Length','0'))
                if not 0<n<=4096: raise ValueError('body length')
                body=json.loads(self.rfile.read(n))
                if self.path=='/api/connect': link.connect(body['port'])
                elif self.path=='/api/action': link.action(body['name'],body.get('config'))
                elif self.path=='/api/motor-tests':
                    with link.lock: rows=list(link.history)
                    return self.send(200,tests.save(body,rows,link.demo,link.folder))
                else: return self.send(404,{'error':'not found'})
                return self.send(200,{'ok':True})
            except (ValueError,KeyError,TypeError) as exc: return self.send(400,{'error':str(exc)})
            except Exception as exc: return self.send(500,{'error':str(exc)})
    return Handler


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--demo',action='store_true');p.add_argument('--port',type=int,default=18866)
    p.add_argument('--open',action='store_true');args=p.parse_args()
    link=Link(args.demo)
    try:
        server=LocalServer(('127.0.0.1',args.port),make_handler(link,secrets.token_hex(24),args.port))
        print(f'Balance console http://127.0.0.1:{args.port} demo={args.demo}',flush=True)
        if args.open: webbrowser.open(f'http://127.0.0.1:{args.port}')
        server.serve_forever()
    finally: link.close()

if __name__=='__main__': main()
