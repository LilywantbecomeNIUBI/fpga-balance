"""Bootstrap the frozen R4 host from a clone. Does not connect or run motors."""
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
    launcher = ROOT/'releases/MOTOR_MANUAL_20261028_R4/launcher.py'
    return subprocess.run([str(python), str(launcher), *sys.argv[1:]], cwd=ROOT).returncode

if __name__ == '__main__':
    raise SystemExit(main())
