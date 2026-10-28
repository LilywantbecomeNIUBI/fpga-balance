'use strict';
const testKeys=['current_target_ma','current_ma','duration_ms','foc_kp','foc_ki'];
const testDefaults={axis:2,current_target_ma:150,current_ma:200,duration_ms:2000,foc_kp:16384,foc_ki:256,zeroCurrent:true,note:''};
let savedTests=[];
function testProfile(){return Object.fromEntries(testKeys.map(k=>[k,Number($('test_'+k).value)]).concat([['zeroCurrent',$('test_zero').checked]]));}
function loadTest(p){
 $('test_axis_select').value=p.axis??p.test_axis??2;
 testKeys.forEach(k=>$('test_'+k).value=p[k]);$('test_zero').checked=p.zeroCurrent??true;
 $('test_note').value=p.note??'';
}
try{loadTest({...testDefaults,...JSON.parse(localStorage.getItem('motor-test-profile')||'{}')});}catch(_){loadTest(testDefaults);}
function customMessage(text,kind='busy'){$('test_result').textContent=text;$('test_result').className='trial-result '+kind;}
window.updateCustomTest=()=>{
 const s=lastState,r=s?.record;
 $('test_run').disabled=trialBusy||!$('test_ready').checked||!s?.connected||!s?.fresh||s?.demo||!r?.drive||r.active||r.armed||r.running||r.commissioning||r.current_calibrating||r.attitude_calibrating;
 $('test_restore_defaults').disabled=trialBusy;
 document.querySelectorAll('#test_history button').forEach(b=>b.disabled=trialBusy);
};
async function refreshTests(){
 try{
  const response=await fetch('/api/motor-tests');if(!response.ok)throw Error('读取历史失败');savedTests=await response.json();
  const body=$('test_history');body.replaceChildren();
  for(const t of savedTests){
   const tr=document.createElement('tr'),c=t.config,s=t.summary;
   const dq=s.tail_m2_dq;
   const values=[new Date(t.saved_wall*1000).toLocaleTimeString(),'M'+c.test_axis,c.current_target_ma+' / '+c.current_ma,c.foc_kp+' / '+c.foc_ki,c.duration_ms,
    s.net_degrees.toFixed(2)+'°',dq?(dq.iq_a*1000).toFixed(1)+' / '+(dq.id_a*1000).toFixed(1):'无实际 dq',t.note||'—'];
   for(const value of values){const td=document.createElement('td');td.textContent=value;tr.append(td);}
   const td=document.createElement('td'),load=document.createElement('button'),download=document.createElement('a');
   load.textContent='载入参数';load.onclick=()=>{if(!trialBusy)loadTest({...c,note:t.note,zeroCurrent:t.current_zero_requested});};
   download.textContent='JSON';download.href='/api/motor-tests/'+t.id;download.download='motor-test-'+t.id+'.json';
   td.append(load,document.createTextNode(' '),download);tr.append(td);body.append(tr);
  }
  if(!savedTests.length){const tr=document.createElement('tr'),td=document.createElement('td');td.colSpan=9;td.textContent='尚无自定义测试记录';tr.append(td);body.append(tr);}
  updateCustomTest();
 }catch(e){$('test_storage').textContent=e.message;}
}
$('test_ready').onchange=()=>updateCustomTest();
$('test_restore_defaults').onclick=()=>loadTest(testDefaults);
$('test_history_refresh').onclick=refreshTests;
$('test_run').onclick=async()=>{
 if(trialBusy||!$('test_ready').checked)return;
 const axis=Number($('test_axis_select').value),profile=testProfile(),note=$('test_note').value;
 // Validate before sending any command, or disabling the form.
 try{M2Trial.makeConfig(config(),lastState?.record||{},axis,profile);}catch(e){customMessage(e.message,'fail');return;}
 try{localStorage.setItem('motor-test-profile',JSON.stringify({...profile,axis,note}));}catch(_){}
 let startedWall=null,appliedConfig=null;
 trialBusy=true;trialCancelled=false;updateButtons();updateCustomTest();
 const io={cancelled:()=>trialCancelled,now:()=>performance.now(),wall:()=>Date.now()/1000,sleep:ms=>new Promise(resolve=>setTimeout(resolve,ms)),
  state:async()=>{const r=await fetch('/api/state');if(!r.ok)throw Error('读取状态失败');return r.json();},
  action:async(name,c)=>{const body={name};if(c)body.config=c;if(!await post('/api/action',body))throw Error($('error').textContent||'命令失败');},
  samples:async()=>{const r=await fetch('/api/m2-test-samples');if(!r.ok)throw Error('读取样本失败');return r.json();},
  config,configured:c=>{appliedConfig=c;boolKeys.forEach(k=>$(k).checked=c[k]);numKeys.forEach(k=>$(k).value=c[k]);$('mode_select').value=c.mode;dirty=false;},
  started:t=>{startedWall=t;},progress:customMessage};
 try{
  const result=await M2Trial.run(io,axis,profile);
  let text=result.ok?`测试已限时结束：M${axis}，编码器净位移 ${result.netDegrees.toFixed(2)}°，覆盖 ${result.spanMs.toFixed(0)} ms。\n`:'测试未完成：'+result.error+'\n';
  if(startedWall!==null){
   const response=await fetch('/api/motor-tests',{method:'POST',headers:{'Content-Type':'application/json','X-Balance-Token':token},
    body:JSON.stringify({started_wall:startedWall,ended_wall:Date.now()/1000,config:appliedConfig,outcome:result.ok?'completed':result.error,note,current_zero_requested:profile.zeroCurrent})});
   const record=await response.json();if(!response.ok)throw Error(record.error||'保存记录失败');
   const s=record.summary,d=s.tail_m2_dq;
   if(d)text+=`M2 末段 ${s.tail_samples} 样本均值：Iq ${(d.iq_a*1000).toFixed(1)} mA / Id ${(d.id_a*1000).toFixed(1)} mA\nUd ${d.ud.toFixed(4)} / Uq ${d.uq.toFixed(4)}；D/Q 限幅占比 ${(s.d_saturated_fraction*100).toFixed(0)}% / ${(s.q_saturated_fraction*100).toFixed(0)}%\n`;
   else text+='当前诊断帧不提供所选电机的实际 dq，不能以指令电流代替实际电流。\n';
   text+=`抽样相电流峰值 ${s.sampled_phase_peak_a?.toFixed(3)??'—'} A。记录已保存，可在下表下载。\n`;
   $('test_storage').textContent='记录目录：'+record.log_dir.replace(/[^\\/]+$/,'motor_tests');
  }else text+='未发出运行；原始事件仍由串口日志记录。\n';
  text+='转动或 Iq 接近目标均不能单独证明电角标定、相序或电流环正常。';
  customMessage(text,result.ok&&result.pass?'pass':'fail');
 }catch(e){customMessage('测试或保存异常：'+e.message+'；请查看串口原始记录。','fail');}
 finally{trialBusy=false;await poll();updateCustomTest();await refreshTests();}
};
refreshTests();updateCustomTest();
