"""Independent local console. Default demo; live requires explicit connection.
One serial owner, no Nano dependency, no firmware programming or automatic ARM.
"""
import argparse
import csv
from dataclasses import fields
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
from pathlib import Path
import secrets
import threading
import time
import webbrowser

from protocol import Config, Stream, command

ROOT = Path(__file__).resolve().parents[1]


class Session:
    def __init__(self, live=False, profile='p30_gmr', connector=None):
        self.live = live
        self.profile_name = profile
        self.profile = json.loads((ROOT / 'config/motors.json').read_text(encoding='utf-8'))['profiles'][profile]
        self.connector = connector
        self.lock = threading.RLock()
        self.changed = threading.Condition(self.lock)
        self.closed = threading.Event()
        self.serial = None
        self.port = None
        self.parser = Stream()
        self.last = None
        self.imu_diag = None
        self.diag_received = 0.0
        self.received = 0.0
        self.sequence = 0
        self.config = None
        self.config_seq = None
        self.intent = False
        self.browser_hb = 0.0
        self.sent_hb = 0.0
        self.error = None
        self.events = []
        self.log_dir = None
        self.rx_log = self.event_log = self.csv_log = None
        self.writer = None
        self.thread = threading.Thread(target=self.worker, daemon=True)
        self.thread.start()

    def event(self, name, **data):
        row = dict(time=datetime.now().isoformat(timespec='milliseconds'), event=name, **data)
        self.events.append(row)
        self.events = self.events[-60:]
        if self.event_log:
            self.event_log.write(json.dumps(row, ensure_ascii=False) + '\n')
            self.event_log.flush()

    def fresh(self):
        return self.serial is not None and self.last is not None and time.monotonic() - self.received < .15

    def send(self, name, payload=b''):
        if self.serial is None: raise ValueError('串口未连接')
        self.sequence = (self.sequence + 1) & 255
        self.serial.write(command(name, self.sequence, payload))
        if name != 'heartbeat': self.event('command', command=name, sequence=self.sequence, payload=payload.hex())
        return self.sequence

    def stop(self, reason='user_stop'):
        with self.lock:
            self.intent = False
            if self.serial and self.last is not None:
                self.send('stop')
            self.event('stop', reason=reason)

    def disconnect(self):
        with self.lock:
            try:
                if self.serial: self.stop('disconnect')
            finally:
                if self.serial: self.serial.close()
                self.serial = None
                self.last = None
                self.imu_diag = None
                self.diag_received = 0.0
                self.intent = False
                self.config = None
                self.config_seq = None
                for handle in (self.rx_log, self.event_log, self.csv_log):
                    if handle: handle.close()
                self.rx_log = self.event_log = self.csv_log = self.writer = None

    def connect(self, port):
        if not self.live: raise ValueError('当前是离线演示；请使用启动菜单的实机控制台')
        if not isinstance(port, str) or not port.strip() or len(port) > 200:
            raise ValueError('请选择实际串口')
        with self.lock:
            self.disconnect()
            if self.connector is None:
                try: import serial
                except ImportError as exc: raise ValueError('请先安装 requirements.txt，或使用启动.cmd建立离线依赖') from exc
                connector = serial.Serial
            else: connector = self.connector
            self.serial = connector(port.strip(), 115200, timeout=.01, write_timeout=.1)
            self.port = port.strip()
            self.parser = Stream()
            self.sequence = 0
            self.last = None
            self.received = 0
            self.error = None
            self.log_dir = ROOT / 'results' / (datetime.now().strftime('%Y%m%d_%H%M%S_') + secrets.token_hex(3))
            self.log_dir.mkdir(parents=True)
            self.rx_log = (self.log_dir / 'rx.bin').open('wb')
            self.event_log = (self.log_dir / 'events.jsonl').open('w', encoding='utf-8')
            self.csv_log = (self.log_dir / 'samples.csv').open('w', encoding='utf-8-sig', newline='')
            self.writer = csv.writer(self.csv_log)
            self.event('connect', port=self.port, profile=self.profile_name)
            # Wait passively for the unique protocol before writing any byte.

    def wait_for(self, predicate, since, timeout=.8):
        end = time.monotonic() + timeout
        with self.changed:
            while time.monotonic() < end:
                if self.fresh() and self.received > since and predicate(self.last): return
                self.changed.wait(min(.04, max(.001, end - time.monotonic())))
        raise ValueError('未收到 FPGA 确认；检查固件、停止状态和拒绝计数')

    def action(self, data):
        name = data.get('action')
        if name == 'connect': self.connect(data.get('port')); return
        if name == 'disconnect': self.disconnect(); return
        if name == 'stop': self.stop(); return
        with self.lock:
            if name == 'heartbeat':
                self.browser_hb = time.monotonic()
                return
            if not self.live or not self.fresh(): raise ValueError('需要实机新鲜遥测')
            since = self.received
            if name == 'config':
                if self.last['armed'] or self.intent: raise ValueError('先停止，再应用参数')
                allowed = {f.name for f in fields(Config)}
                values = data.get('config', {})
                if not isinstance(values, dict) or set(values) - allowed: raise ValueError('参数名称不匹配')
                config = Config(**values)
                payload = config.payload()
                seq = self.send('config', payload)
                self.config = None
                self.config_seq = None
            elif name in ('clear', 'zero'):
                if self.last['armed'] or self.intent: raise ValueError('运行中不能清除故障或重新校零')
                seq = self.send(name)
            elif name == 'arm':
                if self.intent or self.last['armed']: raise ValueError('已解锁')
                if not self.config or self.config_seq != self.last['config_sequence']:
                    raise ValueError('请先应用并确认本次配置')
                expected = data.get('config')
                if not isinstance(expected, dict) or Config(**expected).payload() != self.config.payload():
                    raise ValueError('表单与已应用参数不同，请先应用参数')
                if not self.last['drive_capable']: raise ValueError('观察固件不能驱动电机')
                if self.last.get('pin_profile') != 'carrier_m2_23_30':
                    raise ValueError('板上仍为旧分散引脚固件，请按M2接线方案更换配套固件')
                for side in ('left', 'right'):
                    if self.last[side + '_cpr'] != self.profile[side + '_cpr']:
                        raise ValueError('固件CPR与上位机配置不一致，请使用配套构建')
                if self.last['faults']: raise ValueError('先清除已查明的故障')
                if self.config.mode == 0: raise ValueError('观察模式不能解锁')
                if self.config.mode in (3, 4) and (not self.last['calibrated'] or not self.last['imu_healthy']):
                    raise ValueError('直立模式需要IMU有效、静止姿态校零完成')
                self.intent = True
                self.browser_hb = time.monotonic()
                seq = self.send('arm')
            elif name == 'target':
                if not self.intent or not self.last['armed'] or not self.config: raise ValueError('请先显式解锁')
                self.send('target', self.config.target(data.get('value'), self.last['left_cpr'], self.last['right_cpr']))
                return
            else: raise ValueError('未知操作')
        if name == 'config':
            self.wait_for(lambda s: s['config_valid'] and s['config_sequence'] == seq, since)
            with self.lock:
                self.config, self.config_seq = config, seq
                (self.log_dir / 'config.json').write_text(json.dumps(config.to_dict(), ensure_ascii=False, indent=2), encoding='utf-8')
                self.event('config_ack', config=config.to_dict())
        elif name == 'arm':
            try: self.wait_for(lambda s: s['armed'], since)
            except Exception:
                self.stop('arm_not_confirmed')
                raise
        else:
            self.wait_for(lambda s: s['last_sequence'] == seq and (name != 'clear' or s['faults'] == 0), since)

    def check_link(self, now):
        if self.intent and (now - self.browser_hb > .6 or not self.fresh()):
            self.stop('browser_or_telemetry_timeout')
        elif self.intent and now - self.sent_hb >= .05:
            self.send('heartbeat')
            self.sent_hb = now

    def worker(self):
        while not self.closed.wait(.005):
            try:
                with self.lock:
                    if not self.serial: continue
                    raw = self.serial.read(min(4096, max(1, self.serial.in_waiting)))
                    if raw:
                        self.rx_log.write(raw)
                        for status in self.parser.feed(raw):
                            if status.get('_type') == 'imu_diagnostics':
                                old = self.imu_diag
                                self.imu_diag = status
                                self.diag_received = time.monotonic()
                                if old is None or (old['last_error'], old['who_am_i']) != (status['last_error'], status['who_am_i']):
                                    self.event('imu_diagnostics', data=status)
                                continue
                            first = self.last is None
                            previous = self.last
                            self.last = status
                            self.received = time.monotonic()
                            if first:
                                self.sequence = status['last_sequence']
                                self.send('stop')
                                self.event('identified', cpr=[status['left_cpr'], status['right_cpr']], drive=status['drive_capable'])
                                self.writer.writerow(['host_time', *status.keys()])
                            self.writer.writerow([datetime.now().isoformat(), *[json.dumps(v, ensure_ascii=False) if isinstance(v, list) else v for v in status.values()]])
                            self.csv_log.flush()
                            if previous and previous['armed'] and not status['armed']:
                                self.intent = False
                                self.event('disarmed', faults=status['faults'], reason=status['stop_reason'])
                            self.changed.notify_all()
                    self.check_link(time.monotonic())
            except Exception as exc:
                with self.lock:
                    self.error = str(exc)
                    self.intent = False
                    try: self.disconnect()
                    except Exception: pass

    def state(self):
        with self.lock:
            status = self.last
            if not self.live:
                status = dict(armed=False, calibrated=False, calibrating=False, config_valid=False,
                              imu_healthy=False, drive_capable=False, mode=0, faults=1,
                              pitch_deg=2 * math.sin(time.monotonic()), rate_dps=0,
                              left_position=0, right_position=0, left_velocity=0, right_velocity=0,
                              left_pwm=0, right_pwm=0, left_invalid=0, right_invalid=0, speed_trim_deg=0,
                              left_cpr=self.profile['left_cpr'], right_cpr=self.profile['right_cpr'])
            return dict(demo=not self.live, fresh=self.fresh(), connected=self.serial is not None,
                        imu_diagnostics=self.imu_diag if self.fresh() and time.monotonic()-self.diag_received < 1 else None,
                        port=self.port, status=status, error=self.error, crc_failures=self.parser.bad_crc,
                        profile=self.profile, profile_name=self.profile_name,
                        config=self.config.to_dict() if self.config else None,
                        events=list(self.events), log_dir=str(self.log_dir) if self.log_dir else None)

    def close(self):
        self.closed.set()
        self.thread.join(timeout=1)
        self.disconnect()


def serve(session, port=8878, open_page=False):
    token = secrets.token_urlsafe(32)
    html = (ROOT / 'host/index.html').read_text(encoding='utf-8').replace('__TOKEN__', token)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args): pass

        def reply(self, code, value, kind='application/json; charset=utf-8'):
            raw = (json.dumps(value, ensure_ascii=False) if kind.startswith('application/json') else value).encode('utf-8')
            try:
                self.send_response(code)
                self.send_header('Content-Type', kind)
                self.send_header('Content-Length', str(len(raw)))
                self.send_header('Cache-Control', 'no-store')
                self.end_headers()
                self.wfile.write(raw)
            except ConnectionError:
                # Closing/reloading a page may abort a pending state/STOP reply.
                # The serial action has already been handled independently.
                return

        def do_GET(self):
            if self.path == '/': self.reply(200, html, 'text/html; charset=utf-8')
            elif self.path == '/api/state': self.reply(200, session.state())
            elif self.path == '/api/ports':
                if not session.live: self.reply(200, []); return
                try:
                    import serial.tools.list_ports
                    self.reply(200, [dict(device=p.device, description=p.description) for p in serial.tools.list_ports.comports()])
                except ImportError: self.reply(200, [])
            else: self.reply(404, {'error': 'Not found'})

        def do_POST(self):
            try:
                expected = f'http://127.0.0.1:{self.server.server_port}'
                if self.headers.get('X-Balance-Token') != token or self.headers.get('Origin') not in (None, expected):
                    self.reply(403, {'error': '页面令牌不匹配，请刷新'}); return
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= 16384: raise ValueError('Invalid request length')
                if self.path != '/api/action': self.reply(404, {'error': 'Not found'}); return
                data = json.loads(self.rfile.read(length))
                if not isinstance(data, dict): raise ValueError('Expected object')
                session.action(data)
                self.reply(200, {'ok': True})
            except (ValueError, TypeError, OSError) as exc: self.reply(400, {'error': str(exc)})

    server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    print(f'Brushed balance {"DEMO" if not session.live else "LIVE / disconnected"}: http://127.0.0.1:{port}', flush=True)
    if open_page: webbrowser.open(f'http://127.0.0.1:{port}')
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally: server.server_close(); session.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--live', action='store_true', help='Enable explicit serial connection from the page')
    parser.add_argument('--demo', action='store_true')
    parser.add_argument('--profile', choices=('p30_gmr', 'p30_hall'), default='p30_gmr')
    parser.add_argument('--port', type=int, default=8878, help='Local HTTP port, not serial port')
    parser.add_argument('--open', action='store_true')
    args = parser.parse_args()
    if args.live and args.demo: parser.error('Choose live or demo')
    serve(Session(args.live, args.profile), args.port, args.open)
