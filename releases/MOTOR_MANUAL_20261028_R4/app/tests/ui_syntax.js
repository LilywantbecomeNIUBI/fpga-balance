
const token='__TOKEN__',$=id=>document.getElementById(id);
const boolKeys=['m1_reverse','m2_reverse','axis_confirmed','m1_accepted','m2_accepted'];
const numKeys=['kp','kd','trim_deg','current_ma','duration_ms','start_deg','cutoff_deg','filter_shift','foc_kp','foc_ki','test_axis','current_target_ma','speed_target_rpm','speed_kp','speed_ki'];
let dirty=true,lastState=null,noticeError=false,trialBusy=false,trialCancelled=false;
function config(){const c={mode:Number($('mode_select').value)};boolKeys.forEach(k=>c[k]=$(k).checked);numKeys.forEach(k=>c[k]=Number($(k).value));return c;}
document.querySelectorAll('input,select').forEach(e=>e.addEventListener('input',()=>{dirty=true;$('ack').textContent='参数已修改，尚未应用';updateButtons();}));
async function post(path,body){try{const r=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json','X-Balance-Token':token},body:JSON.stringify(body)});const j=await r.json();if(!r.ok)throw Error(j.error);$('error').textContent='';return true;}catch(e){$('error').textContent=e.message;return false;}}
async function action(name){if(name==='stop'||name==='disconnect')trialCancelled=true;await post('/api/action',{name});await poll();}
$('refresh').onclick=async()=>{const p=await(await fetch('/api/ports')).json();$('ports').replaceChildren(...p.map(x=>{const o=document.createElement('option');o.value=x.port;o.textContent=x.port+' · '+x.description;return o;}));};
$('connect').onclick=async()=>{await post('/api/connect',{port:$('ports').value});dirty=true;await poll();};
$('disconnect').onclick=()=>action('disconnect');$('stop').onclick=()=>action('stop');
window.addEventListener('keydown',e=>{if(e.key==='Escape'){e.preventDefault();action('stop');}});
$('apply').onclick=async()=>{if(await post('/api/action',{name:'config',config:config()})){dirty=false;$('ack').textContent='等待完整参数回显…';}await poll();};
document.querySelectorAll('[data-action]').forEach(b=>b.onclick=()=>action(b.dataset.action));
function updateButtons(){const s=lastState,r=s?.record,live=s&&!s.demo&&s.connected&&s.fresh;
 document.querySelectorAll('input,select').forEach(e=>e.disabled=trialBusy);
 $('m1_trial').disabled=trialBusy||!live||!r?.drive||r?.active||r?.armed||r?.commissioning||r?.current_calibrating||r?.attitude_calibrating;
 $('m2_trial').disabled=trialBusy||!live||!r?.drive||r?.active||r?.armed||r?.commissioning||r?.current_calibrating||r?.attitude_calibrating;
 $('connect').disabled=trialBusy||!!s?.demo;$('apply').disabled=trialBusy||!live||r?.active||r?.armed||r?.commissioning||r?.current_calibrating||r?.attitude_calibrating;
 document.querySelectorAll('[data-action]').forEach(b=>{const n=b.dataset.action;let ok=live&&!trialBusy;
 if(n!=='clear')ok=ok&&s.config_ack&&!dirty&&!r?.estop&&(!r?.motor_faults||(n==='attitude_zero'&&!r?.drive));
 if(['commission_m1','commission_m2','arm','start'].includes(n))ok=ok&&r.drive&&((parseInt(r.config_hex.slice(6,8),16)&224)===224);
 if(n==='commission_m1'||n==='commission_m2')ok=ok&&r.independent_commission&&(r.preserve_commission_on_clear||!(r.commissioned_mask&(n==='commission_m1'?1:2)));
 if(n==='arm'||n==='start')ok=ok&&((r.gates&4095)===4095);
 if(n==='start')ok=ok&&r.armed;
 if(['current_zero','attitude_zero','commission_m1','commission_m2'].includes(n))ok=ok&&!r?.active&&!r?.armed&&!r?.commissioning&&!r?.current_calibrating&&!r?.attitude_calibrating;
 b.disabled=!ok;});}
function plot(id,rows,columns,colors,minRange){const el=$(id),dpr=window.devicePixelRatio||1,w=el.clientWidth,h=el.clientHeight;el.width=w*dpr;el.height=h*dpr;const c=el.getContext('2d');c.scale(dpr,dpr);c.clearRect(0,0,w,h);let bound=minRange;
 rows.forEach(r=>columns.forEach(i=>{if(Number.isFinite(r[i]))bound=Math.max(bound,Math.abs(r[i]));}));bound*=1.15;
 c.strokeStyle='#e4eaf1';c.fillStyle='#7c8ba0';c.font='10px sans-serif';for(let i=0;i<5;i++){const y=12+(h-30)*i/4;c.beginPath();c.moveTo(42,y);c.lineTo(w-6,y);c.stroke();c.fillText((bound*(1-i/2)).toFixed(bound<1?3:1),2,y+3);}if(rows.length<2)return;
 const end=rows.at(-1)[0],start=Math.max(rows[0][0],end-5),span=Math.max(.1,end-start);
 columns.forEach((col,j)=>{c.strokeStyle=colors[j];c.lineWidth=1.5;c.beginPath();let begun=false;rows.forEach(r=>{if(r[0]<start||!Number.isFinite(r[col]))return;const x=42+(r[0]-start)/span*(w-48),y=12+(h-30)*(1-r[col]/bound)/2;if(!begun){c.moveTo(x,y);begun=true;}else c.lineTo(x,y);});c.stroke();});c.fillStyle='#7c8ba0';c.fillText('最近 5 秒',w-65,h-3);}
async function poll(){try{const resp=await fetch('/api/state');if(!resp.ok)throw Error('服务不可用');const s=await resp.json();lastState=s;const r=s.record;
 $('mode').textContent=s.demo?'模拟演示 · 无硬件':!r?'未识别集成固件':r.drive?'驱动版 · 单次受控试运行':'观察版 · 电机输出固定关闭';$('mode').className='pill '+(s.demo?'demo':r?.drive?'drive':'');
 $('notice').textContent=s.demo?'模拟演示：所有数据均为生成数据，控制按钮已禁用。集成 V2 尚未完成整车验收。':s.message;
 $('notice').className=(!s.demo&&r&&(!s.fresh||r.estop||r.motor_faults))?'error':'';
 const fixed=(v,d=2)=>Number.isFinite(v)?v.toFixed(d):'—';$('pitch').textContent=fixed(r?.pitch);$('rate').textContent=fixed(r?.rate);$('shadow').textContent=fixed(r?.shadow_a,3);$('age').textContent=r?.age_us??'—';
 $('gates').replaceChildren(...s.gates.map((g,i)=>{const d=document.createElement('div');const ok=!!(r&&(r.gates&(1<<i)));d.className='gate'+(ok?' ok':'');d.textContent=(ok?'✓ ':'○ ')+g;return d;}));
 $('state').textContent=!r?'DISCONNECTED':!s.fresh?'STALE':r.active?'平衡试运行':r.commissioning?'电角标定中':r.armed?'已解锁 · 请立即开始':r.attitude_calibrating?'姿态校零 '+r.zero_progress+'/1024':'停止';
 $('faults').textContent=r?'停机原因 0x'+r.stop_reason.toString(16)+' / 电机故障 0x'+r.motor_faults.toString(16)+' / 已标定：右轮 '+((r.commissioned_mask&1)?'是':'否')+'、左轮 '+((r.commissioned_mask&2)?'是':'否')+' / 本次标定 M'+r.commission_axis:'等待遥测';
 if(!dirty)$('ack').textContent=s.config_ack?'✓ FPGA 完整参数回显已确认':'参数未确认 / 已失效';
 const d=r?.m2_diagnostic; $('m2_diag').textContent=!d?'当前为精简版或尚未收到诊断帧':`Id 参考 ${fixed(d.id_ref_a,4)} A  | 实际 ${fixed(d.id_a,4)} A\nIq 参考 ${fixed(d.iq_ref_a,4)} A  | 实际 ${fixed(d.iq_a,4)} A\nUd ${fixed(d.ud,5)}  | Uq ${fixed(d.uq,5)}\n电角 ${fixed(d.theta*360/65536,2)}°  | 编码器 ${d.mechanical}\nM2 零位 ${d.learned_zero[1]}  | 电角反向 ${!!(d.learned_reverse&2)}\n序号 ${d.sequence}  | Park有效 ${d.park_valid}  | overrun ${d.overrun}\n运行 ${d.running}  | 标定 ${d.alignment}`;
 $('log').textContent='静止预检：'+s.stationary_preflight+' · 自动记录：'+s.log_dir;$('debug').textContent=JSON.stringify({stats:s.stats,...r},null,2);
 const rows=s.history;plot('attitude',rows,[1,2],['#1966d2','#db861e'],2);plot('torque',rows,[3],['#1966d2'],.01);plot('speed',rows,[4,5],['#1966d2','#db861e'],5);plot('current',rows,[6,7,8,9,10,11],['#1966d2','#149ea5','#945fd4','#db861e','#d34048','#788394'],.01);updateButtons();
 }catch(e){$('notice').textContent='上位机连接中断；FPGA 心跳超时将停止驱动。请检查本地服务。';$('notice').className='error';lastState=null;updateButtons();}}
$('save_config').onclick=()=>{const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([JSON.stringify({schema:'balance-v2',config:config()},null,2)],{type:'application/json'}));a.download='balance-v2-parameters.json';a.click();URL.revokeObjectURL(a.href);};
$('load_config').onchange=async e=>{try{const j=JSON.parse(await e.target.files[0].text());if(j.schema!=='balance-v2')throw Error('仅接受 balance-v2 参数');const c=j.config;if(['axis_y','pitch_reverse','upright_z_positive','encoder1_reverse','encoder2_reverse'].some(k=>k in c))throw Error('旧参数含可选方向；请使用本车固定方向的新参数');boolKeys.forEach(k=>{if(typeof c[k]!=='boolean')throw Error(k);});numKeys.forEach(k=>{if(!Number.isFinite(c[k]))throw Error(k);});boolKeys.forEach(k=>$(k).checked=c[k]);numKeys.forEach(k=>$(k).value=c[k]);['axis_confirmed','m1_accepted','m2_accepted'].forEach(k=>$(k).checked=false);$('mode_select').value=c.mode;dirty=true;updateButtons();$('ack').textContent='已导入到表单，尚未发送；请检查车轮方向确认位';}catch(x){$('error').textContent=x.message;}};

function trialMessage(text,kind){const el=$('m2_trial_result');el.textContent=text;el.className='trial-result '+kind;}
async function startMotorTrial(axis){
 if(trialBusy)return;trialBusy=true;trialCancelled=false;updateButtons();
 const io={cancelled:()=>trialCancelled,now:()=>performance.now(),wall:()=>Date.now()/1000,sleep:ms=>new Promise(resolve=>setTimeout(resolve,ms)),
  state:async()=>{const r=await fetch('/api/state');if(!r.ok)throw Error('读取状态失败');return r.json();},
  action:async(name,c)=>{const body={name};if(c)body.config=c;if(!await post('/api/action',body))throw Error($('error').textContent||'命令失败');},
  samples:async()=>{const r=await fetch('/api/m2-test-samples');if(!r.ok)throw Error('读取编码器记录失败');return r.json();},
  config,configured:c=>{boolKeys.forEach(k=>$(k).checked=c[k]);numKeys.forEach(k=>$(k).value=c[k]);$('mode_select').value=c.mode;dirty=false;},
  progress:text=>trialMessage(text,'busy')};
 try{const r=await M2Trial.run(io,axis);
  if(!r.ok)trialMessage('试转未完成：'+r.error,'fail');
  else {const detail=`M${axis}：ΔEncoder ${r.netTicks} tick (${r.netDegrees.toFixed(2)}°)，范围 ${r.rangeTicks} tick；${r.samples}个运行样本 / ${r.spanMs.toFixed(0)} ms。`;
   if(!r.conclusive)trialMessage('记录不足，不能判定电机是否持续旋转。\n'+detail,'fail');
   else if(r.pass)trialMessage('编码器检测到持续转动，本次试转通过。\n'+detail+'\n此结果不代表标定与相序完全验收。','pass');
   else trialMessage('电机未检测到持续旋转：可能相序接反、缺相或零位错误，也可能电流环未跟踪。\n'+detail,'fail');
  }
 }finally{trialBusy=false;updateButtons();await poll();}
};

$('m1_trial').onclick=()=>startMotorTrial(1);
$('m2_trial').onclick=()=>startMotorTrial(2);
fetch('/api/vehicle-parameters').then(r=>r.json()).then(p=>{$('m1_reverse').checked=p.m1.forward_torque_reverse;$('m2_reverse').checked=p.m2.forward_torque_reverse;}).catch(()=>{});
$('refresh').click();poll();setInterval(poll,200);
