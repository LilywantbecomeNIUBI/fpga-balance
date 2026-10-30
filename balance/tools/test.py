"""Focused RTL + host tests. Uses behavioral FOC model only for routing test."""
from pathlib import Path
import json,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];BASE=ROOT/'balance';sys.path.insert(0,str(BASE/'host'))
from protocol import Config,command,frame

def protocol_bench():
    frames=[frame(Config(kp=.1).body(42)),command('start',43)]
    old_orientation=bytearray(Config(kp=.2).body(45));old_orientation[3]^=2
    old_wheel_direction=bytearray(Config(kp=.2).body(46));old_wheel_direction[27]^=4
    current_old_time=bytearray(Config(mode=1).body(53));current_old_time[24:26]=(1000).to_bytes(2,'little')
    current_no_cap=bytearray(Config(mode=1).body(54));current_no_cap[30:32]=bytes(2)
    def send(f):return '\n'.join(f'send(8\'d{b});' for b in f)
    return '''`timescale 1ns/1ps
module tb_protocol;
reg clk=0;always #10 clk=~clk;reg rst=0,bv=0,can=1,inv=0;reg [7:0] b=0;
wire cv,configured,changed;wire [7:0] cmd,ack,result;wire [255:0] cfg;wire [15:0] errors;
balance_protocol dut(clk,rst,bv,b,can,inv,cv,cmd,configured,changed,cfg,ack,result,errors);
task send(input [7:0] value);begin @(negedge clk);b=value;bv=1;@(negedge clk);bv=0;end endtask
initial begin repeat(3)@(negedge clk);rst=1;
'''+send(frames[0])+'''
#1;if(!configured || ack!=42 || cfg[63:32]!=1677722 || cfg[31:24]!=8'h03)$fatal(1,"config decode");
can=0;
'''+send(frame(Config(kp=.2).body(44)))+'''
#1;if(result!=3 || cfg[63:32]!=1677722)$fatal(1,"busy config mutated");
can=1;
'''+send(frame(bytes(old_orientation)))+'''
#1;if(result!=2 || cfg[63:32]!=1677722 || cfg[26:24]!=3)$fatal(1,"old orientation profile accepted");
'''+send(frame(bytes(old_wheel_direction)))+'''
#1;if(result!=2 || cfg[63:32]!=1677722 || cfg[219:218]!=1)$fatal(1,"old wheel direction profile accepted");
'''+send(frames[0][:-4]+b'000\n')+'''
#1;if(errors==0 || cfg[63:32]!=1677722)$fatal(1,"bad CRC accepted");
'''+send(frames[1])+'''
#1;if(!cv || cmd!=7)$fatal(1,"valid start command lost");
'''+send(command('commission_m2',47))+'''
#1;if(!cv || cmd!=10)$fatal(1,"explicit M2 command lost");
'''+send(command('commission_m1',48))+'''
#1;if(!cv || cmd!=9)$fatal(1,"explicit M1 command lost");
'''+send(frame(bytes([2,49,5])+bytes(29)))+'''
#1;if(cv || result!=2)$fatal(1,"legacy next-axis command accepted");
'''+send(frame(Config().body(50)))+'''
#1;if(!configured || result!=0 || cfg[207:192]!=0)$fatal(1,"continuous config rejected");
'''+send(frame(Config(kp=1.0,kd=.2,current_ma=1200,mode=2,speed_target_rpm=120,speed_kp=.510,speed_ki=.4).body(52)))+'''
#1;if(result!=0 || cfg[63:32]!=16777216 || cfg[95:64]!=3355443 || cfg[159:144]!=1200 || !cfg[222] || cfg[247:240]!=255 || cfg[239:224]!=1200)$fatal(1,"expanded PD config rejected");
'''+send(frame(bytes(current_old_time)))+'''
#1;if(result!=2 || cfg[217:216]!=2)$fatal(1,"obsolete timed current mode accepted");
'''+send(frame(bytes(current_no_cap)))+'''
#1;if(result!=2 || cfg[217:216]!=2)$fatal(1,"current mode missing speed ceiling accepted");
'''+send(frame(Config(mode=1,current_speed_limit_rpm=123).body(55)))+'''
#1;if(result!=0 || cfg[217:216]!=1 || cfg[207:192]!=0 || cfg[255:240]!=1230)$fatal(1,"continuous current config rejected");
'''+send(command('pause',51))+'''
#1;if(!cv || cmd!=11 || !configured)$fatal(1,"normal end protocol invalidated config");
send("@");send("0");send("X");#1;if(!cv || cmd!=1)$fatal(1,"priority stop");
inv=1;@(negedge clk);inv=0;#1;if(configured)$fatal(1,"manual clear invalidation");
$display("PASS atomic CRC config, busy reject, corrupted frame reject, commands, priority stop");$finish;end
endmodule
'''

def main():
    out=BASE/'results/tests';out.mkdir(parents=True,exist_ok=True)
    generated=out/'tb_protocol.sv';generated.write_text(protocol_bench(),encoding='ascii')
    results=[]
    for tb in sorted((BASE/'tests').glob('tb_*.sv'))+[generated]:
        sources=sorted((BASE/'src').glob('*.v'))
        if tb.stem=='tb_command_deadline':sources+=[ROOT/'motor_control/src/motor_command_guard.v']
        if tb.stem in ('tb_telemetry_dual','tb_telemetry','tb_telemetry_m2'):sources+=[ROOT/'motor_control/src/motor_console.v']
        if tb.stem in ('tb_dual_current','tb_dual_iq','tb_top_shadow','tb_top_commission','tb_top_reconfigure','tb_imu_startup','tb_independent_commission','tb_clear_compat','tb_simplified','tb_m2_trace'):
            sources+=sorted((ROOT/'motor_control/src').glob('*.v'))+sorted((ROOT/'motor_control/tests/models').glob('*.sv'))
        if tb.stem=='tb_imu_reader':sources+=sorted((BASE/'vendor/imu').glob('*.v'))+sorted((BASE/'tests/models').glob('*.sv'))
        if tb.stem=='tb_imu_startup':sources+=sorted((BASE/'vendor/imu').glob('*.v'))+sorted((BASE/'tests/models').glob('*.sv'))
        if tb.stem in ('tb_top_shadow','tb_top_commission','tb_top_reconfigure'):sources+=sorted((BASE/'vendor/imu').glob('*.v'))
        build=subprocess.run(['iverilog','-g2012','-s',tb.stem,'-o',str(out/(tb.stem+'.out')),*map(str,sources),str(tb)],capture_output=True,text=True,timeout=60)
        code=build.returncode;text=build.stdout+build.stderr
        if code==0:
            run=subprocess.run(['vvp',str(out/(tb.stem+'.out'))],capture_output=True,text=True,timeout=60)
            code=run.returncode;text+=run.stdout+run.stderr
        passed=code==0 and 'PASS ' in text
        results.append(dict(test=tb.stem,passed=passed,build_exit=build.returncode,exit=code,output=text));print(tb.stem,passed,'exit='+str(code),text.strip(),flush=True)
        (out/(tb.stem+'.log')).write_text(text,encoding='utf-8')
    tests=subprocess.run([sys.executable,'-m','unittest','discover','-s',str(BASE/'tests'),'-p','test_*.py','-v'],capture_output=True,text=True)
    print(tests.stdout,tests.stderr,flush=True)
    (out/'host.log').write_text(tests.stdout+tests.stderr,encoding='utf-8')
    (out/'result.json').write_text(json.dumps(dict(rtl=results,host_exit=tests.returncode),indent=2),encoding='utf-8')
    return 0 if tests.returncode==0 and all(r['passed'] for r in results) else 1
if __name__=='__main__':sys.exit(main())
