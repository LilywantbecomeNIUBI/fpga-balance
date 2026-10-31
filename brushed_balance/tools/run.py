"""Bootstrap this folder's console using the bundled pySerial wheel."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

if __name__ == '__main__':
    if sys.version_info < (3, 10): raise SystemExit('Python 3.10+ required')
    python = ROOT / '.venv' / ('Scripts/python.exe' if os.name == 'nt' else 'bin/python')
    if not python.exists(): subprocess.run([sys.executable, '-m', 'venv', str(ROOT / '.venv')], check=True)
    if subprocess.run([str(python), '-c', 'import serial'], capture_output=True).returncode:
        subprocess.run([str(python), '-m', 'pip', 'install', '--no-index', '--find-links', str(ROOT / 'vendor/wheels'), '-r', str(ROOT / 'requirements.txt')], check=True)
    raise SystemExit(subprocess.call([str(python), str(ROOT / 'host/server.py'), '--open', *sys.argv[1:]], cwd=ROOT))
