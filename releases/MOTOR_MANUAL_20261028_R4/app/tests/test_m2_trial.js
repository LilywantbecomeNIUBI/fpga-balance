const assert=require('node:assert/strict');
const T=require('../host/m2_test.js');
const base={m1_reverse:true,m2_reverse:true,axis_confirmed:true,m1_accepted:true,m2_accepted:true,kp:.1,kd:.01,foc_kp:16384,foc_ki:256};
const initial={host_time:100,time_us:0,angles:[0,16000],drive:true,commissioned_mask:3,current_calibrated:true,current_calibrating:false,attitude_calibrated:true,attitude_calibrating:false,commissioning:false,active:false,armed:false,running:false,config_hex:'020008e0',motor_faults:0,stop_reason:0,commission_failed:false};
function samples(step,oscillate=false){return Array.from({length:400},(_,i)=>({host_time:101+i*.005,time_us:i*5000,angles:[0,(16000+(oscillate?(i%2?40:-40):step*(i+1))+16384)%16384],active:true}));}
let r=T.measure(samples(5),initial,101);assert(r.pass);assert.equal(r.netTicks,2000);assert.equal(r.samples,400);
r=T.measure(samples(0,true),initial,101);assert(!r.pass);assert(r.rangeTicks>0);
r=T.measure(samples(0).map((s,i)=>({...s,angles:[0,(16000+(i?500:0))%16384]})),initial,101);assert(!r.pass,'single twitch must not count as sustained rotation');
r=T.measure(samples(-5),initial,101);assert(r.pass);assert.equal(r.netTicks,-2000);
r=T.measure(samples(5).slice(0,5),initial,101);assert(!r.conclusive&&!r.pass);
function fake({cancelAt,faultAt,missingMask,failAction}={}){
 let t=0,wall=101,phase='',activeAt=null,cancel=false;const calls=[];const rec={...initial,angles:[...initial.angles]};if(missingMask!==undefined)rec.commissioned_mask=missingMask;
 const state=()=>{
  if(phase==='run'&&t-activeAt>=2000){rec.active=false;rec.running=false;}
  if(faultAt!==undefined&&phase==='run'&&t-activeAt>=faultAt)rec.motor_faults=4;
  return {connected:true,fresh:true,demo:false,config_ack:phase!=='config',record:{...rec}};
 };
 const io={now:()=>t,wall:()=>wall,cancelled:()=>cancel,config:()=>base,configured:()=>{},progress:()=>{},
  state:async()=>state(),sleep:async ms=>{t+=ms;if(phase==='config')phase='ready';if(cancelAt&&phase===cancelAt)cancel=true;},
  action:async(n,c)=>{calls.push([n,c]);if(n===failAction)throw Error('simulated command failure');
   if(n==='config'){phase='config';rec.attitude_calibrated=false;}
   if(n==='attitude_zero'){phase='attitude';rec.attitude_calibrated=true;}
   if(n==='current_zero'){phase='current';rec.current_calibrated=true;}
   if(n==='arm'){phase='arm';rec.armed=true;}
   if(n==='start'){phase='run';activeAt=t;rec.active=true;rec.running=true;rec.armed=false;}
   if(n==='stop'){phase='stop';rec.active=false;rec.running=false;rec.armed=false;}
  },samples:async()=>({samples:samples(5)})};return {io,calls};
}
(async()=>{
 let f=fake();r=await T.run(f.io);assert(r.ok&&r.pass);assert.deepEqual(f.calls.map(v=>v[0]),['config','attitude_zero','current_zero','arm','start']);
 const c=f.calls[0][1];assert.equal(c.mode,1);assert.equal(c.test_axis,2);assert.equal(c.current_target_ma,400);assert.equal(c.current_ma,500);assert.equal(c.duration_ms,2000);assert.equal(c.m2_reverse,false);assert.equal(c.kp,0);
 f=fake({cancelAt:'attitude'});r=await T.run(f.io);assert(!r.ok);assert(!f.calls.some(v=>v[0]==='start'));assert.equal(f.calls.at(-1)[0],'stop');
 f=fake({faultAt:500});r=await T.run(f.io);assert(!r.ok);assert.equal(f.calls.at(-1)[0],'stop');
 f=fake({missingMask:2});r=await T.run(f.io);assert(!r.ok);assert.equal(f.calls.length,0);
 f=fake({failAction:'config'});r=await T.run(f.io);assert(!r.ok);assert(!f.calls.some(v=>v[0]==='arm'));assert.equal(f.calls.at(-1)[0],'stop');
 f=fake();r=await T.run(f.io,1);assert(r.ok);assert.equal(f.calls[0][1].test_axis,1);assert.equal(f.calls.filter(v=>v[0]==='start').length,1);
 const m1samples=samples(5).map(r=>({...r,angles:[r.angles[1],0]}));assert(T.measure(m1samples,{angles:[16000,0]},101,2000,1).pass);
 const profile={current_target_ma:-150,current_ma:200,duration_ms:2000,foc_kp:8192,foc_ki:128,zeroCurrent:false};
 f=fake();r=await T.run(f.io,2,profile);assert(r.ok);assert.equal(f.calls[0][1].current_target_ma,-150);assert.equal(f.calls[0][1].foc_kp,8192);assert(!f.calls.some(v=>v[0]==='current_zero'));
 f=fake();r=await T.run(f.io,2,{...profile,duration_ms:1000});assert(r.ok,'runtime follows custom duration, not fixed 2s');
 for(const change of [{current_target_ma:201},{duration_ms:5001},{foc_kp:16385},{foc_ki:257},{current_target_ma:NaN}]){
  f=fake();r=await T.run(f.io,2,{...profile,...change});assert(!r.ok);assert.equal(f.calls.length,0,'invalid custom profile must not send commands');
 }
 f=fake({cancelAt:'attitude'});r=await T.run(f.io,2,profile);assert(!r.ok);assert(!f.calls.some(v=>v[0]==='start'));assert.equal(f.calls.at(-1)[0],'stop');
 console.log('PASS M1 and M2 one-click exact config, ordered ack/zero/arm/start, encoder wrap, twitch rejection, incomplete capture, cancellation, faults and missing commissioning');
})().catch(e=>{console.error(e);process.exit(1)});
