// Historical records only. This module sends no hardware commands.
'use strict';
async function refreshTests(){
 try{const response=await fetch('/api/motor-tests');if(!response.ok)throw Error('读取记录失败');const rows=await response.json();$('test_history').replaceChildren();
 for(const t of rows){const c=t.config,s=t.summary,d=s.tail_dq??s.tail_m2_dq;const tr=document.createElement('tr');
 const values=[new Date(t.saved_wall*1000).toLocaleTimeString(),'M'+c.test_axis,c.current_target_ma+' / '+c.current_ma,(c.test_axis===2?(c.foc_kp_m2??c.foc_kp):c.foc_kp)+' / '+(c.test_axis===2?(c.foc_ki_m2??c.foc_ki):c.foc_ki),c.duration_ms??'持续',s.net_degrees.toFixed(2)+'°',d?(d.iq_a*1000).toFixed(1)+' / '+(d.id_a*1000).toFixed(1):'无实际dq',t.note||'—'];
 for(const v of values){const td=document.createElement('td');td.textContent=v;tr.append(td);}const td=document.createElement('td'),a=document.createElement('a');a.href='/api/motor-tests/'+t.id;a.download='motor-test-'+t.id+'.json';a.textContent='JSON';td.append(a);tr.append(td);$('test_history').append(tr);}
 $('test_storage').textContent=rows.length?'历史记录只读，载入不会启动电机。':'暂无历史记录';
 }catch(e){$('test_storage').textContent=e.message;}}
$('test_history_refresh').onclick=refreshTests;refreshTests();
