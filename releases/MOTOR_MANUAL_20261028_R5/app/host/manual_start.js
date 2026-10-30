(function(root){
'use strict';
async function run(io){
 let issued=false;
 function cancel(){if(io.cancelled())throw Error('已取消启动');}
 async function state(){cancel();const s=await io.state();cancel();const r=s.record;
  if(s.demo||!s.connected||!s.fresh||!r||!s.config_ack||r.motor_faults||r.stop_reason||r.commission_failed)throw Error('参数未确认、故障锁存或数据失联');return s;}
 try{
  const s=await state(),r=s.record;
  if(!r.drive||r.active||r.commissioning||r.current_calibrating||r.attitude_calibrating||(r.gates&3615)!==3615)throw Error('启动条件未齐全');
  issued=true;cancel();await io.action('arm');
  const end=io.now()+700;
  while(!(await state()).record.armed){if(io.now()>end)throw Error('解锁超时');await io.sleep(20);}
  cancel();await io.action('start');
  return {ok:true};
 }catch(e){if(issued){try{await io.action('stop');}catch(_){}}return {ok:false,error:e.message};}
}
if(typeof module!=='undefined'&&module.exports)module.exports={run};else root.ManualStart={run};
})(typeof window!=='undefined'?window:globalThis);
