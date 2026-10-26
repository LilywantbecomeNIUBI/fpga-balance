"""Create a source-only checksum manifest. No hardware or network access."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[1]
def files():
 for p in sorted(ROOT.rglob('*')):
  if not p.is_file():continue
  r=p.relative_to(ROOT)
  if any(n in {'.git','.venv','__pycache__','build','results','dist'} for n in r.parts):continue
  if r.as_posix().startswith('motor_control/ip/'):continue
  if p.name=='SOURCE_MANIFEST.json' or p.suffix in {'.pyc','.out','.fs','.bin','.zip'}:continue
  yield p
def main():
 values={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files()}
 (ROOT/'SOURCE_MANIFEST.json').write_text(json.dumps(dict(sha256=values),indent=2),encoding='utf-8');print('Sealed',len(values),'files')
if __name__=='__main__':main()
