import copy
import csv
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from tools.audit_pins import audit


class PinTests(unittest.TestCase):
    def setUp(self):
        with (ROOT/'constraints/pins.csv').open(encoding='utf-8') as handle:self.rows=list(csv.DictReader(handle))
        self.top=(ROOT/'rtl/brushed_balance_top.sv').read_text(encoding='utf-8')

    def test_contiguous_header_matches_carrier_reference(self):
        report=audit(self.rows,self.top)
        self.assertEqual(report['physical_pins'],30)
        self.assertEqual(report['ground_pins'],[21,22])

    def test_duplicate_ball_and_wrong_carrier_mapping_are_rejected(self):
        rows=copy.deepcopy(self.rows);rows[0]['ball']=rows[1]['ball']
        with self.assertRaises(ValueError):audit(rows,self.top)
        rows=copy.deepcopy(self.rows)
        next(r for r in rows if r['signal']=='right_enc_a')['p7']='27'
        with self.assertRaises(ValueError):audit(rows,self.top)

    def test_encoder_output_alias_and_reversed_direction_are_rejected(self):
        rows=copy.deepcopy(self.rows)
        next(r for r in rows if r['signal']=='right_enc_b')['direction']='OUT'
        with self.assertRaises(ValueError):audit(rows,self.top)
        with self.assertRaises(ValueError):audit(self.rows,self.top+'\nassign legacy_m2_disable=0;\n')


if __name__=='__main__':unittest.main()
