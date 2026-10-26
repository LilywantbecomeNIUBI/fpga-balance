"""Focused RTL + host tests. Uses behavioral FOC model only for routing test."""
from pathlib import Path
import json,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];BASE=ROOT/'balance';sys.path.insert(0,str(BASE/'host'))
from protocol import Config,command,frame

def protocol_bench():
    frames=[frame(Config(kp=.1,axis_confirmed=True,m1_accepted=True,m2_accepted=True).body(42)),command('start',43)]
    def send(f):return '\n'.join(f'send(8\'d{b});' for b in f)
    return '''`timescale 1ns/1ps
module tb_protocol;
reg clk=0;always #10 clk=~clk;reg rst=0,bv=0,can=1,inv=0;reg [7:0] b=0;
wire cv,configured,changed;wire [7:0] cmd,ack,result;wire [255:0] cfg;wire [15:0] errors;
balance_protocol dut(clk,rst,bv,b,can,inv,cv,cmd,configured,changed,cfg,ack,result,errors);
task send(input [7:0] value);begin @(negedge clk);b=value;bv=1;@(negedge clk);bv=0;end endtask
initial begin repeat(3)@(negedge clk);rst=1;
'''+send(frames[0])+'''
#1;if(!configured || ack!=42 || cfg[63:32]!=1677722 || cfg[31:24]!=8'hf1)$fatal(1,"config decode");
can=0;
'''+send(frame(Config(kp=.2).body(44)))+'''
#1;if(result!=3 || cfg[63:32]!=1677722)$fatal(1,"busy config mutated");
can=1;
'''+send(frames[0][:-4]+b'000\n')+'''
#1;if(errors==0 || cfg[63:32]!=1677722)$fatal(1,"bad CRC accepted");
'''+send(frames[1])+'''
#1;if(!cv || cmd!=7)$fatal(1,"valid start command lost");
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
        if tb.stem=='tb_telemetry':sources+=[ROOT/'motor_control/src/motor_console.v']
        if tb.stem in ('tb_dual_iq','tb_top_shadow','tb_imu_startup'):
            sources+=sorted((ROOT/'motor_control/src').glob('*.v'))+sorted((ROOT/'motor_control/tests/models').glob('*.sv'))
        if tb.stem=='tb_imu_reader':sources+=sorted((BASE/'vendor/imu').glob('*.v'))+sorted((BASE/'tests/models').glob('*.sv'))
        if tb.stem=='tb_imu_startup':sources+=sorted((BASE/'vendor/imu').glob('*.v'))+sorted((BASE/'tests/models').glob('*.sv'))
        if tb.stem=='tb_top_shadow':sources+=sorted((BASE/'vendor/imu').glob('*.v'))
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
