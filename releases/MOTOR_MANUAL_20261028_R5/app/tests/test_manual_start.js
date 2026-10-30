const assert=require('node:assert/strict'),T=require('../host/manual_start.js');
async function scenario({cancel=false,gates=3615,failStart=false}={}){
 let time=0,r={drive:true,active:false,armed:false,gates},calls=[];
 const result=await T.run({cancelled:()=>cancel,now:()=>time,sleep:async ms=>{time+=ms;},
 state:async()=>({connected:true,fresh:true,demo:false,config_ack:true,record:r}),
 action:async name=>{calls.push(name);if(name==='arm')r.armed=true;if(name==='start'&&failStart)throw Error('failed');}});
 return {result,calls};
}
(async()=>{
 let s=await scenario();assert(s.result.ok);assert.deepEqual(s.calls,['arm','start']);
 s=await scenario({gates:0});assert(!s.result.ok);assert.deepEqual(s.calls,[]);
 s=await scenario({cancel:true});assert(!s.result.ok);assert.deepEqual(s.calls,[]);
 s=await scenario({failStart:true});assert(!s.result.ok);assert.deepEqual(s.calls,['arm','start','stop']);
 console.log('PASS manual start only arm/start, gates, cancel and failure Stop; no parameter/calibration commands');
})().catch(e=>{console.error(e);process.exit(1)});
