from pathlib import Path
import sys,unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from build_warnings import critical_warnings

class SynthesisWarnings(unittest.TestCase):
    def test_actual_forward_declaration_failure_is_rejected(self):
        text="""Undeclared symbol 'physical_motor_mask', assumed default net type 'wire'("path":99)
WARN  (EX3638) : 'physical_motor_mask' is already implicitly declared on line 99
WARN  (EX1998) : Net 'physical_motor_mask[1]' does not have a driver("path":99)
WARN  (EX2565) : Input 'axis[1]' on this instance is undriven. Assigning to 0, simulation mismatch possible.
"""
        self.assertEqual(len(critical_warnings(text)),4)

    def test_unused_inputs_are_not_missing_drivers(self):
        self.assertEqual(critical_warnings('WARN  (CV0016) : Input adc_dout_b is unused'),[])

if __name__=='__main__':unittest.main()
