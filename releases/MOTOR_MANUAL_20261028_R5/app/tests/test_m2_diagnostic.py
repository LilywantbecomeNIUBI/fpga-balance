import unittest,struct,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'host'))
from protocol import Parser,crc,demo_packet
class DiagnosticTests(unittest.TestCase):
 def packet(self):
  p=bytearray(168);p[:126]=demo_packet(0)[:126];p[3]=168
  struct.pack_into('<IIHH',p,126,1234,5678,11147,65530)
  for off,val in [(138,-512),(140,1024),(142,-512),(144,0),(146,1229),(149,-10),(151,1200),(153,-1000),(155,2000)]:struct.pack_into('<h',p,off,val)
  p[148]=1;p[157]=1
  struct.pack_into('<HHBBBB',p,158,4321,11147,2,2,1,0xd2)
  struct.pack_into('<H',p,166,crc(p[:166]))
  return bytes(p)+bytes([Parser._xor(p)])
 def test_fragment_mixed_and_signed_diagnostic(self):
  parser=Parser();p=self.packet();self.assertEqual(parser.feed(p[:129]),[])
  rows=parser.feed(p[129:]+demo_packet(0));self.assertEqual(len(rows),2)
  d=rows[0]['m2_diagnostic'];self.assertEqual(d['sequence'],1234);self.assertEqual(d['theta'],65530)
  self.assertEqual(d['currents_a'],[-.125,.25,-.125]);self.assertEqual(d['iq_ref_a'],1229/4096)
  self.assertEqual(d['id_a'],-10/4096);self.assertEqual(d['iq_a'],1200/4096)
  self.assertEqual(d['ud'],-1000/32768);self.assertEqual(d['uq'],2000/32768)
  self.assertTrue(d['running'] and d['park_valid']);self.assertFalse(d['alignment'] or d['overrun'])
  self.assertEqual(d['learned_zero'],[4321,11147]);self.assertEqual(d['learned_reverse'],2)
  self.assertEqual(d['selected_motor'],2);self.assertIsNone(rows[1]['m2_diagnostic'])
 def test_corruption_rejected(self):
  p=bytearray(self.packet());p[151]^=1;parser=Parser()
  rows=parser.feed(bytes(p)+demo_packet(0));self.assertEqual(len(rows),1);self.assertIsNone(rows[0]['m2_diagnostic']);self.assertEqual(parser.crc_errors,1)
if __name__=='__main__':unittest.main()
