from pathlib import Path
import sys,unittest,csv,io,time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'host'))
from server import Link
class CsvTests(unittest.TestCase):
 def test_diagnostic_columns(self):
  link=Link(demo=True)
  try:
   end=time.monotonic()+1
   while not link.record and time.monotonic()<end:time.sleep(.01)
   with link.lock:
    row=dict(link.record);row['m2_diagnostic']=dict(sequence=123,theta=44,id_ref_a=.25,iq_ref_a=0,id_a=.105,iq_a=-.033,ud=.125,uq=.125,park_valid=True,overrun=False,learned_zero=[0,6731],learned_reverse=2)
    link.history.clear();link.history.append(row)
    rows=list(csv.DictReader(io.StringIO(link.csv().decode('utf-8-sig'))))
   self.assertEqual(rows[0]['m2_sequence'],'123');self.assertEqual(rows[0]['m2_id_a'],'0.105');self.assertEqual(rows[0]['m2_zero'],'6731');self.assertIsNone(rows[0].get(None))
  finally:link.close()
if __name__=='__main__':unittest.main()
