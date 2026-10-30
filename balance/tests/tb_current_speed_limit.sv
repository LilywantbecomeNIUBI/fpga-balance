`timescale 1ns/1ps
module tb_current_speed_limit;
reg clk=0;always #10 clk=~clk;reg rst=0,en=0;reg signed [15:0] cmd=400,r1=0,r2=0;reg [15:0] cap=1000;
wire signed [15:0] q1,q2;wire l1,l2;
balance_current_speed_limit dut(clk,rst,en,cmd,r1,r2,cap,q1,q2,l1,l2);
task settle;begin repeat(200)@(negedge clk);end endtask
initial begin repeat(3)@(negedge clk);rst=1;en=1;settle;
if(q1!=400 || q2!=400)$fatal(1,"below ceiling did not preserve Iq");
r1=875;r2=-1000;settle;if(q1!=200 || q2!=0 || !l1 || !l2)$fatal(1,"positive/negative speed derating");
cmd=-400;r1=-875;r2=750;settle;if(q1!=-200 || q2!=-400)$fatal(1,"negative current polarity changed");
r1=-1100;r2=1100;settle;if(q1 || q2)$fatal(1,"overspeed torque not zero");
r1=0;r2=0;settle;if(q1!=-400 || q2!=-400)$fatal(1,"did not recover after slowdown");
en=0;r1=2000;settle;if(q1!=-400 || q2!=-400 || l1 || l2)$fatal(1,"non-current bypass changed");
en=1;cap=0;settle;if(q1 || q2)$fatal(1,"zero ceiling invalid");
$display("PASS current-mode speed governor both axes, signed current/speed, ramp, recovery and bypass");$finish;
end
endmodule
