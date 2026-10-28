(function(root){
'use strict';
const DURATION_MS=2000,MIN_TICKS=256;
const wrap=d=>((d+8192)%16384+16384)%16384-8192;
function makeConfig(base,record,axis=2,profile=null){
 const c={...base},flags=record.config_hex?parseInt(record.config_hex.slice(6,8),16):0;
 Object.assign(c,{mode:1,test_axis:axis,current_target_ma:400,current_ma:500,duration_ms:DURATION_MS,
  m1_reverse:false,m2_reverse:false,kp:0,kd:0,speed_target_rpm:0,speed_kp:0,speed_ki:0});
 if(profile){
  Object.assign(c,{trim_deg:0,start_deg:3,cutoff_deg:15,filter_shift:8});
  for(const [k,lo,hi] of [['current_target_ma',-1000,1000],['current_ma',1,1000],['duration_ms',100,5000],['foc_kp',0,16384],['foc_ki',0,256]]){
   if(!Number.isInteger(profile[k])||profile[k]<lo||profile[k]>hi)throw Error(k+' 超出范围 '+lo+'…'+hi);
   c[k]=profile[k];
  }
  if(Math.abs(c.current_target_ma)>c.current_ma)throw Error('Iq 目标不能超过指令电流上限');
 }
 if(![1,2].includes(axis))throw Error('仅允许单轮测试');
 ['axis_confirmed','m1_accepted','m2_accepted'].forEach((k,i)=>c[k]=!!c[k]||!!(flags&(1<<(i+5))));
 if(!c.axis_confirmed||!c.m1_accepted||!c.m2_accepted)throw Error('请先确认姿态与两路电机确认项；数值参数由按钮自动设置');
 return c;
}
function measure(samples,baseline,startedWall,durationMs=DURATION_MS,axis=2){
 const seen=new Set(),rows=samples.filter(r=>r.host_time>=startedWall&&r.active&&!seen.has(r.time_us)&&seen.add(r.time_us));
 let previous=baseline.angles[axis-1],net=0,path=0,low=0,high=0;const bins=[0,0,0,0];
 const first=rows.length?rows[0].time_us:0;
 for(const r of rows){const d=wrap(r.angles[axis-1]-previous);previous=r.angles[axis-1];net+=d;path+=Math.abs(d);low=Math.min(low,net);high=Math.max(high,net);
  const dt=(r.time_us-first)>>>0;bins[Math.min(3,Math.floor(dt/(durationMs*1000/4)))]+=d;}
 const spanMs=rows.length?((rows.at(-1).time_us-first)>>>0)/1000:0;
 const direction=Math.sign(net),progressBins=bins.filter(v=>direction*v>=16).length;
 const enough=rows.length>=20&&spanMs>=durationMs-250;
 return {pass:enough&&Math.abs(net)>MIN_TICKS&&progressBins>=3,conclusive:enough,netTicks:net,netDegrees:net*360/16384,
  rangeTicks:high-low,pathTicks:path,samples:rows.length,spanMs,progressBins,thresholdTicks:MIN_TICKS};
}
async function run(io,axis=2,profile=null){
 let issued=false,complete=false;
 const checkCancel=()=>{if(io.cancelled())throw Error('已取消试转');};
 async function get(){checkCancel();const s=await io.state();checkCancel();
  if(s.demo||!s.connected||!s.fresh||!s.record)throw Error('串口未连接或遥测已过期');
  const r=s.record;if(r.motor_faults||r.stop_reason||r.commission_failed)throw Error('故障或停止锁存中，请先人工处理并清故障');return s;}
 async function send(n,c){checkCancel();issued=true;await io.action(n,c);checkCancel();}
 async function wait(pred,timeout,label,minMs=0){const start=io.now();while(true){const s=await get();
  if(io.now()-start>=minMs&&pred(s))return s;
  if(io.now()-start>timeout)throw Error(label+'超时');await io.sleep(40);}}
 try{
  const initial=await get(),r=initial.record;
  if(!r.drive)throw Error('观察版不能试转');
  if(r.active||r.armed||r.commissioning||r.current_calibrating||r.attitude_calibrating)throw Error('请先等待当前操作结束');
  if(r.commissioned_mask!==3)throw Error('当前固件要求M1/M2两路电角标定均完成；本按钮不会自动标定');
  const cfg=makeConfig(io.config(),r,axis,profile);io.configured(cfg);io.progress(`应用参数：M${axis} ${cfg.current_target_ma} mA，上限${cfg.current_ma} mA，${cfg.duration_ms} ms`);
  if(profile){
   io.progress('等待两轮滑行停稳后再校零');
   let windowAt=io.now(),angles=[...r.angles],stillSince=io.now();
   await wait(s=>{const now=io.now();if(now-windowAt<250)return false;
    const still=s.record.angles.every((a,i)=>Math.abs(wrap(a-angles[i]))<=8);
    if(!still)stillSince=now;angles=[...s.record.angles];windowAt=now;
    return still&&now-stillSince>=750;},15000,'等待停稳');
  }
  await send('config',cfg);await wait(s=>s.config_ack,1800,'参数确认');
  io.progress('自动姿态校零');await send('attitude_zero');await wait(s=>s.record.attitude_calibrated&&!s.record.attitude_calibrating,6500,'姿态校零',150);
  if(profile?.zeroCurrent!==false){io.progress('自动电流校零');await send('current_zero');await wait(s=>s.record.current_calibrated&&!s.record.current_calibrating,3000,'电流校零',150);}
  else if(!(await get()).record.current_calibrated)throw Error('尚无有效电流零点，请勾选重新校零');
  io.progress(`解锁并开始M${axis}单次试转`);await send('arm');const armed=await wait(s=>s.record.armed,700,'解锁');
  const baseline=armed.record,startedWall=io.wall();io.started?.(startedWall,cfg);await send('start');
  await wait(s=>s.record.active||s.record.running,700,'启动');io.progress(`M${axis}试转中：${cfg.current_target_ma} mA，${cfg.duration_ms} ms 后自动结束`);
  await wait(s=>!s.record.active&&!s.record.running&&!s.record.armed,cfg.duration_ms+1500,'运行结束');
  const capture=await io.samples();checkCancel();const result=measure(capture.samples,baseline,startedWall,cfg.duration_ms,axis);
  complete=true;return {ok:true,config:cfg,startedWall,...result};
 }catch(error){if(issued&&!complete){try{await io.action('stop');}catch(_){}}
  return {ok:false,error:error.message};}
}
const api={DURATION_MS,MIN_TICKS,makeConfig,measure,run};
if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.M2Trial=api;
})(typeof window!=='undefined'?window:globalThis);
