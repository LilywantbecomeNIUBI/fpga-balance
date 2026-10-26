"""One entrypoint. Creates an isolated venv using the bundled PyPI wheel."""
from pathlib import Path
import argparse,os,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('action',choices=['demo','console','check','test','build-observe','build-drive']);p.add_argument('--port',type=int,default=18866);a=p.parse_args()
 if sys.version_info<(3,10):raise SystemExit('Python3.10+ required')
 env=ROOT/'.venv';python=env/('Scripts/python.exe' if os.name=='nt' else 'bin/python')
 if not python.exists():subprocess.run([sys.executable,'-m','venv',str(env)],check=True)
 if subprocess.run([str(python),'-c','import serial; assert serial.VERSION=="3.5"'],capture_output=True).returncode:
  subprocess.run([str(python),'-m','pip','install','--no-index','--find-links',str(ROOT/'vendor/wheels'),'-r',str(ROOT/'requirements.txt')],check=True)
 if a.action in ('demo','console'):
  args=['balance/host/server.py','--port',str(a.port),'--open']+(['--demo'] if a.action=='demo' else [])
 elif a.action=='test':args=['balance/tools/test.py']
 elif a.action=='check':args=['tools/selfcheck.py']
 else:args=['balance/tools/build.py','--profile',a.action.split('-')[1]]
 return subprocess.run([str(python),*args],cwd=ROOT).returncode
if __name__=='__main__':raise SystemExit(main())
