import unittest,struct,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'host'))
from protocol import Config,Parser,crc,demo_packet
class DualCurrent(unittest.TestCase):
 def test_independent_config(self):
  b=Config(foc_kp=300,foc_ki=16,foc_kp_m2=700,foc_ki_m2=9).body(5)
  self.assertEqual(struct.unpack_from('<HH',b,12),(300,16))
  self.assertEqual(struct.unpack_from('<HH',b,20),(700,9));self.assertTrue(b[27]&128)
  for k,v in [('foc_kp_m2',16385),('foc_ki_m2',257),('foc_kp_m2',1.2)]:
   with self.assertRaises(ValueError):Config(**{k:v}).body(0)
 def test_current_speed_cap_encoding(self):
  b=Config(mode=1,current_speed_limit_rpm=123).body(1)
  self.assertEqual(struct.unpack_from('<H',b,30)[0],1230)
  for v in [0,9,1001,float('nan')]:
   with self.assertRaises(ValueError):Config(mode=1,current_speed_limit_rpm=v).body(0)
 def test_dual_frame_fragmentation(self):
  p=bytearray(200);p[:126]=demo_packet()[:126];p[3]=200;p[165]=0xd2;p[164]=31
  for t,iq in [(126,-820),(166,1230)]:
   struct.pack_into('<IIHH',p,t,42,99,123,456);struct.pack_into('<h',p,t+25,iq);p[t+31]=1
  struct.pack_into('<H',p,198,crc(p[:198]));p=bytes(p)+bytes([Parser._xor(p)])
  a=Parser();self.assertEqual(a.feed(p[:170]),[]);r=a.feed(p[170:])[0]
  self.assertTrue(r['current_continuous_supported']);self.assertTrue(r['current_speed_limit_supported']);self.assertEqual(r['current_speed_limiting'],[True,True]);self.assertTrue(r['dual_current_tuning']);self.assertEqual(r['m1_diagnostic']['iq_a'],1230/4096);self.assertEqual(r['m2_diagnostic']['iq_a'],-820/4096)
  bad=bytearray(p);bad[191]^=1;self.assertEqual(Parser().feed(bad),[])
