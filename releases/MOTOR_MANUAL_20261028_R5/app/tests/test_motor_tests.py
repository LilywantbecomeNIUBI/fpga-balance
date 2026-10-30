from pathlib import Path
import sys,json,time,tempfile,unittest,threading,urllib.request,urllib.error
from types import SimpleNamespace
from unittest.mock import patch
from http.server import ThreadingHTTPServer
from dataclasses import asdict
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'host'))
from protocol import Config
from motor_tests import TestStore,summarize
import server

class MotorRecords(unittest.TestCase):
    def rows(self,axis=2):
        t=time.time()
        return [dict(host_time=t+i*.005,time_us=i*5000,active=True,running=True,
                     angles=[100, (16380+i*5)%16384],currents_a=[.01]*3+[.3,-.2,-.1],motor_faults=0,stop_reason=0,
                     m2_diagnostic=dict(selected_motor=2,running=True,park_valid=True,overrun=False,
                       id_ref_a=0,iq_ref_a=-.15,id_a=.29,iq_a=-.15,ud=-.125,uq=-.5)) for i in range(20)]

    def test_record_survives_store_recreation_and_preserves_raw_data(self):
        rows=self.rows()
        with tempfile.TemporaryDirectory() as folder:
            store=TestStore(Path(folder));body=dict(config=asdict(Config(mode=1,test_axis=2,current_ma=200,current_target_ma=-150)),
                started_wall=rows[0]['host_time'],ended_wall=rows[-1]['host_time'],outcome='completed',note='negative',current_zero_requested=False)
            r=store.save(body,rows,False,'original-log')
            loaded=TestStore(Path(folder)).read(r['id'])
            self.assertEqual(loaded['samples'],rows);self.assertEqual(len(store.recent()),1)
            self.assertEqual(r['summary']['net_degrees'],95*360/16384)
            self.assertAlmostEqual(r['summary']['tail_m2_dq']['id_a'],.29)
            self.assertEqual(r['summary']['d_saturated_fraction'],1)
            self.assertFalse(r['current_zero_requested'])

    def test_m1_does_not_claim_m2_dq(self):
        self.assertIsNone(summarize(self.rows(),1)['tail_m2_dq'])

    def test_invalid_path_and_old_capture_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            store=TestStore(Path(folder))
            with self.assertRaises(ValueError):store.read('../secret')
            with self.assertRaises(ValueError):store.save(dict(config=asdict(Config(mode=1,test_axis=2)),started_wall=1,ended_wall=2),[],False,'log')

    def test_http_save_read_and_auth_without_motor_actions(self):
        rows=self.rows()
        link=SimpleNamespace(lock=threading.RLock(),history=rows,demo=True,folder='test-log')
        with tempfile.TemporaryDirectory() as folder,patch.object(server,'ROOT',Path(folder)):
            http=ThreadingHTTPServer(('127.0.0.1',0),server.make_handler(link,'test',0));port=http.server_address[1]
            http.RequestHandlerClass=server.make_handler(link,'test',port)
            thread=threading.Thread(target=http.serve_forever,daemon=True);thread.start()
            base=f'http://127.0.0.1:{port}'
            body=dict(config=asdict(Config(mode=1,test_axis=2,current_ma=200,current_target_ma=-150)),started_wall=rows[0]['host_time'],ended_wall=rows[-1]['host_time'])
            try:
                req=urllib.request.Request(base+'/api/motor-tests',data=json.dumps(body).encode(),headers={'Content-Type':'application/json','X-Balance-Token':'wrong','Origin':base})
                with self.assertRaises(urllib.error.HTTPError) as error:urllib.request.urlopen(req)
                self.assertEqual(error.exception.code,403)
                req.add_header('X-Balance-Token','test')
                saved=json.load(urllib.request.urlopen(req))
                self.assertTrue(saved['demo'])
                loaded=json.load(urllib.request.urlopen(base+'/api/motor-tests/'+saved['id']))
                self.assertEqual(loaded['samples'],rows)
                self.assertEqual(len(json.load(urllib.request.urlopen(base+'/api/motor-tests'))),1)
            finally:http.shutdown();http.server_close();thread.join()

if __name__=='__main__':unittest.main()
