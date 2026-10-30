from pathlib import Path
import sys,unittest,threading,urllib.request,urllib.error,json
from http.server import ThreadingHTTPServer
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'host'))
from server import Link,make_handler
class TrialEndpointTests(unittest.TestCase):
 def test_read_only_sample_endpoint_and_script(self):
  link=Link(demo=True);server=ThreadingHTTPServer(('127.0.0.1',0),make_handler(link,'test',0));port=server.server_address[1]
  server.RequestHandlerClass=make_handler(link,'test',port);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
  try:
   with link.lock:link.history.append(dict(host_time=1,time_us=2,angles=[3,4],active=True,running=True,motor_faults=0,stop_reason=0))
   data=json.load(urllib.request.urlopen(f'http://127.0.0.1:{port}/api/m2-test-samples'));self.assertTrue(any(r['angles']==[3,4] for r in data['samples']))
   self.assertEqual(len(link.queue),0)
   with self.assertRaises(urllib.error.HTTPError) as e:urllib.request.urlopen(f'http://127.0.0.1:{port}/m2_test.js')
   self.assertEqual(e.exception.code,404)
   text=urllib.request.urlopen(f'http://127.0.0.1:{port}/manual_start.js').read().decode();self.assertIn('ManualStart',text)
  finally:server.shutdown();server.server_close();thread.join();link.close()
if __name__=='__main__':unittest.main()
