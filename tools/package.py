"""Export exactly the sealed source set into a ZIP, never includes old build dirs."""
from pathlib import Path
import hashlib,json,zipfile
ROOT=Path(__file__).resolve().parents[1]
def main():
 data=json.loads((ROOT/'SOURCE_MANIFEST.json').read_text(encoding='utf-8'))
 for name,h in data['sha256'].items():assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==h,name
 target=ROOT/'dist/fpga-balance-20261026.zip';target.parent.mkdir(exist_ok=True)
 with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as z:
  for name in [*data['sha256'],'SOURCE_MANIFEST.json']:z.write(ROOT/name,'fpga-balance/'+name)
 digest=hashlib.sha256(target.read_bytes()).hexdigest()
 target.with_suffix('.zip.sha256').write_text(digest+'  '+target.name+'\n')
 with zipfile.ZipFile(target) as z:assert z.testzip() is None
 print(target);print('SHA256',digest,'bytes',target.stat().st_size)
if __name__=='__main__':main()
