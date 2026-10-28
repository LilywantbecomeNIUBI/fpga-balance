from pathlib import Path
import json, struct, sys, time, unittest,threading,urllib.request,urllib.error
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'host'))
from protocol import Config, Parser, command, crc, demo_packet
from server import Link,make_handler

class ProtocolTests(unittest.TestCase):
    def test_config_layout_bounds(self):
        c=Config(kp=.1,kd=.001,trim_deg=-1.25)
        b=c.body(9)
        self.assertEqual(len(b),32);self.assertEqual(b[:4],bytes([2,9,8,19]))
        self.assertEqual(struct.unpack_from('<h',b,16)[0],-125)
        self.assertEqual(struct.unpack_from('<H',b,24)[0],1000)
        for k,v in [('kp',float('nan')),('kp',-.1),('current_ma',1001),('duration_ms',5001),('filter_shift',3),('current_ma',1.5),('m2_accepted',1)]:
            with self.subTest(k=k,v=v),self.assertRaises(ValueError):Config(**{k:v}).body(0)
    def test_v2_modes_and_legacy_rejection(self):
        c=Config(mode=1,test_axis=2,current_target_ma=-50)
        b=c.body(1);self.assertEqual(b[27],37);self.assertEqual(struct.unpack_from('<h',b,28)[0],-50)
        b=Config(mode=2,speed_target_rpm=-12.3,speed_kp=.015,speed_ki=.002).body(3)
        self.assertEqual(b[27],22);self.assertEqual(struct.unpack_from('<h',b,28)[0],-123);self.assertEqual(b[30:],bytes([15,2]))
        for cfg in [Config(mode=3),Config(mode=1,current_target_ma=101),Config(speed_target_rpm=61),Config(speed_kp=.256)]:
            with self.assertRaises(ValueError):cfg.body(0)
        old=bytearray(demo_packet(1));old[2]=1;struct.pack_into('<H',old,126,crc(old[:126]));old[128]=Parser._xor(old[:128])
        self.assertEqual(Parser().feed(old),[])

    def test_vehicle_orientation_is_not_a_runtime_option(self):
        self.assertEqual(Config().body(0)[3]&7,3)
        self.assertEqual(Config(m1_reverse=True,axis_confirmed=True).body(0)[3]&7,3)
        self.assertEqual(Config().body(0)[27]&12,4)
        for key,value in [('axis_y',False),('pitch_reverse',False),('upright_z_positive',True),('encoder1_reverse',False),('encoder2_reverse',True)]:
            with self.subTest(key=key),self.assertRaises(TypeError):Config(**{key:value})

    def test_fragment_crc_resync(self):
        p=Parser();good=demo_packet(1);bad=bytearray(good);bad[24]^=1
        self.assertEqual(p.feed(b'garbage'+bad+good[:30]),[])
        r=p.feed(good[30:]);self.assertEqual(len(r),1);self.assertEqual(r[0]['imu_seq'],1000)
        self.assertFalse(r[0]['drive']);self.assertEqual(r[0]['accel'],[0,0,-1]);self.assertGreater(p.crc_errors,0)
    def test_crc_vector(self):
        self.assertEqual(crc(b'123456789'),0x29b1)
        f=command('start',5);self.assertEqual(len(f),71);self.assertTrue(f.startswith(b'@02050700'))

class LinkTests(unittest.TestCase):
    def setUp(self):self.link=Link(demo=True);time.sleep(.03)
    def tearDown(self):self.link.close()
    def test_demo_never_controls(self):
        for name in ('config','clear','current_zero','attitude_zero','commission_m1','commission_m2','arm','start'):
            with self.subTest(name=name),self.assertRaises(ValueError):self.link.action(name)
        self.assertIsNone(self.link.serial);self.assertTrue(self.link.snapshot()['demo']);self.assertIn(b'demo',self.link.csv())
    def test_config_exact_ack(self):
        with self.link.lock:
            self.link.demo=False
            self.link.pending_config=Config().body(2).hex()
            r=dict(self.link.record);r['configured']=True;r['config_hex']=Config().body(3).hex()
            self.link.accept([r]);self.assertFalse(self.link.config_ack)
            r['config_hex']=self.link.pending_config;self.link.accept([r]);self.assertTrue(self.link.config_ack)
            r['configured']=False;self.link.accept([r]);self.assertFalse(self.link.config_ack)

    def test_observe_attitude_with_motor_fault_keeps_drive_blocked(self):
        class Serial:
            def write(self,b):pass
            def close(self):pass
        with self.link.lock:
            self.link.demo=False;self.link.serial=Serial()
            self.link.record.update(drive=False,motor_faults=1,stop_reason=0)
            self.link.action('config',{})
            r=dict(self.link.record,configured=True,config_hex=self.link.pending_config)
            self.link.accept([r]);self.assertTrue(self.link.config_ack)
            self.link.action('attitude_zero')
            for name in ['commission_m1','commission_m2','arm','start']:
                with self.assertRaises(ValueError):self.link.action(name)
            self.link.record['drive']=True
            with self.assertRaises(ValueError):self.link.action('config',{})
            self.link.accept([dict(self.link.record)]);self.assertFalse(self.link.config_ack)
    def test_missing_m2_stops_start(self):
        class Serial:
            def __init__(self):self.sent=[]
            def write(self,b):self.sent.append(b)
            def close(self):pass
        with self.link.lock:
            self.link.demo=False;self.link.serial=Serial();self.link.config_ack=True
            self.link.record.update(drive=True,configured=True,config_hex=Config(axis_confirmed=True,m1_accepted=True).body(2).hex(),gates=4095)
            with self.assertRaisesRegex(ValueError,'M2'):self.link.action('arm')
            self.assertEqual(self.link.serial.sent,[])
            self.link.action('stop');self.assertEqual(self.link.serial.sent,[b'X'])

    def test_explicit_commission_requires_new_firmware_and_never_substitutes_axis(self):
        class Serial:
            def write(self,b):pass
            def close(self):pass
        with self.link.lock,patch('server.stationary_check',return_value=(True,'ok')):
            self.link.demo=False;self.link.serial=Serial();self.link.config_ack=True
            self.link.record.update(drive=True,configured=True,motor_faults=0,stop_reason=0,
                config_hex=Config(axis_confirmed=True,m1_accepted=True,m2_accepted=True).body(2).hex(),
                independent_commission=False,commissioned_mask=0)
            with self.assertRaisesRegex(ValueError,'固件'):self.link.action('commission_m2')
            self.assertEqual(len(self.link.queue),0)
            self.link.record['independent_commission']=True
            self.link.action('commission_m2')
            self.assertEqual(self.link.queue.pop(),command('commission_m2',self.link.seq))
            self.link.record['commissioned_mask']=2
            with self.assertRaisesRegex(ValueError,'已标定'):self.link.action('commission_m2')
            self.link.action('commission_m1')
            self.assertEqual(self.link.queue.pop(),command('commission_m1',self.link.seq))
            self.link.record['preserve_commission_on_clear']=True
            self.link.action('commission_m2')
            self.assertEqual(self.link.queue.pop(),command('commission_m2',self.link.seq))
            with self.assertRaises(ValueError):self.link.action('commission')
            self.link.record.update(commissioned_mask=0,motor_faults=16)
            with self.assertRaisesRegex(ValueError,'故障'):self.link.action('commission_m2')
    def test_passive_unknown_firmware(self):
        class Serial:
            in_waiting=0
            def __init__(self):self.sent=[]
            def read(self,n):return b''
            def write(self,b):self.sent.append(b)
            def close(self):pass
        with self.link.lock:
            self.link.demo=False;self.link.record=None;self.link.serial=Serial();s=self.link.serial
        time.sleep(.06)
        with self.link.lock:self.assertEqual(s.sent,[])
    def test_timeout_stops_without_auto_clear(self):
        class Serial:
            in_waiting=0
            def __init__(self):self.sent=[]
            def read(self,n):return b''
            def write(self,b):self.sent.append(b)
            def close(self):pass
        with self.link.lock:
            self.link.demo=False;self.link.serial=Serial();s=self.link.serial
            self.link.last_rx=time.monotonic()-1
        time.sleep(.04)
        with self.link.lock:
            self.assertEqual(s.sent,[b'X']);self.assertFalse(self.link.config_ack)
    def test_identification_starts_with_stop(self):
        class Serial:
            in_waiting=129
            def __init__(self):self.sent=[]
            def read(self,n):return demo_packet(1)
            def write(self,b):self.sent.append(b)
            def close(self):pass
        with self.link.lock:
            self.link.demo=False;self.link.record=None;self.link.serial=Serial();s=self.link.serial
            self.link.needs_initial_stop=True
        time.sleep(.04)
        with self.link.lock:
            self.assertGreater(len(s.sent),0);self.assertEqual(s.sent[0],b'X')
            self.assertFalse(self.link.config_ack)
            self.assertTrue(all(b==b'X' or b.startswith(b'@020') for b in s.sent))
    def test_http_origin_and_demo_gate(self):
        server=ThreadingHTTPServer(('127.0.0.1',0),BaseHTTPRequestHandler)
        port=server.server_address[1]
        server.RequestHandlerClass=make_handler(self.link,'test-token',port)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        try:
            url=f'http://127.0.0.1:{port}'
            r=json.load(urllib.request.urlopen(url+'/api/state'));self.assertTrue(r['demo'])
            request=urllib.request.Request(url+'/api/action',data=b'{"name":"start"}',headers={'X-Balance-Token':'bad'})
            with self.assertRaises(urllib.error.HTTPError) as caught:urllib.request.urlopen(request)
            self.assertEqual(caught.exception.code,403)
            request=urllib.request.Request(url+'/api/action',data=b'{"name":"start"}',headers={'X-Balance-Token':'test-token','Origin':'http://evil.invalid'})
            with self.assertRaises(urllib.error.HTTPError) as caught:urllib.request.urlopen(request)
            self.assertEqual(caught.exception.code,403)
            request=urllib.request.Request(url+'/api/action',data=b'{"name":"start"}',headers={'X-Balance-Token':'test-token'})
            with self.assertRaises(urllib.error.HTTPError) as caught:urllib.request.urlopen(request)
            self.assertEqual(caught.exception.code,400)
        finally:server.shutdown();server.server_close();thread.join()

if __name__=='__main__':unittest.main()
