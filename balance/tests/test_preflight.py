from pathlib import Path
import sys,unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'host'))
from server import stationary_check
class StaticTests(unittest.TestCase):
 def rows(self):return [dict(time_us=i*5000,running=False,commissioning=False,current_calibrated=True,motor_faults=0,angles=[16383,2],currents_a=[.001]*6) for i in range(500)]
 def test_pass(self):self.assertTrue(stationary_check(self.rows())[0])
 def test_bias_peak_motion_and_stale(self):
  for kind in ('bias','peak','motion','stale','uncalibrated'):
   r=self.rows()
   if kind=='bias':
    for a in r:a['currents_a'][4]=.145
   elif kind=='peak':r[250]['currents_a'][4]=.23
   elif kind=='motion':r[-1]['angles'][1]=9
   elif kind=='stale':r[-1]['time_us']=5000000
   else:r[-1]['current_calibrated']=False
   with self.subTest(kind=kind):
    ok,message=stationary_check(r)
    self.assertTrue(ok)
    if kind in ('bias','peak'):self.assertIn('Warning:',message)
if __name__=='__main__':unittest.main()
