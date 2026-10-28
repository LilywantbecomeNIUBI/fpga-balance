"""Offline file and configuration checks. Never opens hardware."""
from pathlib import Path
import hashlib,json,shutil,sys
ROOT=Path(__file__).resolve().parents[1]
def main():
 manifest=ROOT/'SOURCE_MANIFEST.json'
 if manifest.exists():
  for name,digest in json.loads(manifest.read_text(encoding='utf-8'))['sha256'].items():
   p=(ROOT/name).resolve()
   if not p.is_relative_to(ROOT) or not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=digest:raise RuntimeError('file changed/missing: '+name)
  print('PASS source manifest')
 sys.path.insert(0,str(ROOT/'balance/host'))
 from protocol import Config,Parser,demo_packet
 assert len(Config().body(0))==32 and len(Parser().feed(demo_packet(1)))==1
 assert Config().body(0)[3]&7==3
 assert Config().body(0)[27]&12==4
 from protocol import COMMANDS
 assert COMMANDS['commission_m1']==9 and COMMANDS['commission_m2']==10 and 'commission' not in COMMANDS
 import serial
 assert serial.VERSION=='3.5'
 top=(ROOT/'balance/src/balance_top.v').read_text(encoding='utf-8')
 assert '.CURRENT_REVERSE(7)' in top and '.GAIN_CH3_Q16(217082)' in top and '.GAIN_CH4_Q16(220767)' in top
 assert '.SELECTABLE_COMMISSION(1)' in top
 attitude=(ROOT/'balance/src/balance_attitude.v').read_text(encoding='utf-8')
 assert 'orientation' not in attitude and '.orientation(' not in top
 profile=json.loads((ROOT/'hardware/active_profile.json').read_text(encoding='utf-8'))
 for name,value in [('CURRENT_REVERSE',profile['current_reverse_mask']),('CURRENT_CB_MASK',profile['current_cb_mask']),('COMMAND_SLEW',profile['command_slew']),('MAX_WINDOW_TICKS',profile['speed_guard_ticks'])]:
  assert '.'+name+'('+str(value)+')' in top,name
 frozen=json.loads((ROOT/'hardware/reference/frozen_pins.json').read_text(encoding='utf-8'))
 for n,h in frozen['constraints_sha256'].items():assert hashlib.sha256((ROOT/'motor_control/constraints'/n).read_bytes()).hexdigest()==h
 print('PASS protocol V2, current mask7, gains, frozen pins and pySerial3.5')
 print('Icarus:',shutil.which('iverilog'),'vvp:',shutil.which('vvp'))
 print('No serial port opened; no FPGA programming or motor commands.')
 return 0
if __name__=='__main__':raise SystemExit(main())
