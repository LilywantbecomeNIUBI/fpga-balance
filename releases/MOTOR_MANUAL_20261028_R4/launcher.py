"""Manual local entry. No motor action on ordinary startup."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,sys,urllib.request,urllib.error,webbrowser
ROOT=Path(__file__).resolve().parent;BASE='http://127.0.0.1:18866';RELEASE=ROOT.name
if hasattr(sys.stdout,'reconfigure'):sys.stdout.reconfigure(encoding='utf-8')
def verify():
 m=json.loads((ROOT/'MANIFEST.json').read_text(encoding='utf-8'))
 for name,digest in m['files'].items():
  if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest:raise RuntimeError('固定文件发生变化: '+name)
 return m
def state():
 try:return json.load(urllib.request.urlopen(BASE+'/api/state',timeout=1))
 except (urllib.error.URLError,TimeoutError):return None
def start():
 s=state()
 if s:
  if s.get('release_id')!=RELEASE:raise RuntimeError('18866被旧上位机占用。请先关闭旧上位机控制台，再启动固定版。')
  webbrowser.open(BASE);print('固定版已在运行，已打开页面。');return
 print('关闭本控制台会结束服务；页面中的 Stop 或 Esc 可停止电机。')
 subprocess.run([sys.executable,str(ROOT/'app/host/server.py'),'--port','18866','--open'],check=True)
def program(which):
 m=json.loads((ROOT/'MANIFEST.json').read_text(encoding='utf-8'));f=m['firmware'][which];bit=ROOT/f['file']
 if hashlib.sha256(bit.read_bytes()).hexdigest()!=f['sha256']:raise RuntimeError('位流校验不一致: '+str(bit))
 print('即将下载: '+f['label']+' (SRAM only, 不写Flash)')
 if input('请断开电机12V，保留逻辑供电。已完成请输入 OFF: ').strip().upper()!='OFF':print('已取消');return
 s=state()
 if s:
  page=urllib.request.urlopen(BASE,timeout=2).read().decode();token=re.search("const token='([^']+)'",page).group(1)
  q=urllib.request.Request(BASE+'/api/action',data=b'{"name":"disconnect"}',headers={'Content-Type':'application/json','X-Balance-Token':token,'Origin':BASE})
  urllib.request.urlopen(q,timeout=2).close()
 runtime=json.loads((ROOT/'runtime.json').read_text());cmd=[runtime['programmer'],'--cable-index','1','--location','290','--device','GW5AT-138B','--operation_index','2','--fsFile',str(bit)]
 subprocess.run(cmd,check=True)
 print('下载完成。回页面重新连接串口；上电后重新应用参数、校零和电角标定。')
def main():
 p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--start',action='store_true');p.add_argument('--program',choices=['simple','diagnostic']);a=p.parse_args()
 if a.check:verify();print('PASS 固定文件校验');return
 if a.start:start();return
 if a.program:program(a.program);return
 while True:
  print('\n电机手动调试 固定版 R4\n  1 启动/打开上位机（默认，不下载、不运行电机）\n  2 下载 M2诊断版 到SRAM\n  3 下载 精简版 到SRAM\n  4 打开数据记录文件夹\n  5 打开操作说明\n  0 退出')
  choice=input('选择 [1]: ').strip() or '1'
  if choice=='0':return
  try:
   if choice=='1':start()
   elif choice=='2':program('diagnostic')
   elif choice=='3':program('simple')
   elif choice=='4':
    import os
    folder=ROOT/'app/results';folder.mkdir(exist_ok=True);os.startfile(folder)
   elif choice=='5':
    import os
    os.startfile(ROOT/'使用说明.txt')
  except (Exception,KeyboardInterrupt) as e:print('已结束: '+str(e))
if __name__=='__main__':main()
