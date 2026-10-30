"""Bootstrap the frozen R5 host from a clone. Does not connect or run motors."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def main():
    if sys.version_info < (3, 10):
        raise SystemExit('Python 3.10+ required')
    env = ROOT/'.venv'
    python = env/('Scripts/python.exe' if os.name == 'nt' else 'bin/python')
    if not python.exists():
        subprocess.run([sys.executable, '-m', 'venv', str(env)], check=True)
    if subprocess.run([str(python), '-c', 'import serial; assert serial.VERSION=="3.5"'], capture_output=True).returncode:
        subprocess.run([str(python), '-m', 'pip', 'install', '--no-index', '--find-links',
                        str(ROOT/'vendor/wheels'), '-r', str(ROOT/'requirements.txt')], check=True)
    args = sys.argv[1:]
    release = 'MOTOR_MANUAL_20261028_R4'  # preserve the archived R4 START.cmd
    if args[:1] == ['--release']:
        if len(args)<2 or args[1] not in ('MOTOR_MANUAL_20261028_R4','MOTOR_MANUAL_20261028_R5'):
            raise SystemExit('Unknown manual release')
        release,args = args[1],args[2:]
    launcher = ROOT/'releases'/release/'launcher.py'
    return subprocess.run([str(python), str(launcher), *args], cwd=ROOT).returncode

if __name__ == '__main__':
    raise SystemExit(main())
