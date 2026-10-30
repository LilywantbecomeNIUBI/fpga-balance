`timescale 1ns/1ps
module tb_math;
 reg clk=0;always #10 clk=~clk;
 reg rst=0,start=0;reg signed [16:0] x=0,y=0;wire done;wire signed [31:0] angle;
 balance_atan atan(clk,rst,start,x,y,done,angle);
 task check_angle(input integer a,input integer b,input integer expected);
 begin @(negedge clk);x=a;y=b;start=1;@(negedge clk);start=0;wait(done);#1;
 if(angle-expected>400 || angle-expected < -400) $fatal(1,"atan %d,%d got %d want %d",a,b,angle,expected);
 @(negedge clk);end endtask
 reg sample=0,zero=0,invalidate=0;
 reg signed [15:0] ax=0,ay=0,az=-8192,gx=0,gy=8,gz=0;
 reg [31:0] ts=0;wire av,cal,busy,bad;wire signed [31:0] pitch,rate;wire [15:0] dt,progress;
 balance_attitude #(.ZERO_LOG2(3)) attitude(clk,rst,sample,zero,invalidate,4'd8,
 ax,ay,az,gx,gy,gz,ts,av,cal,busy,bad,pitch,rate,dt,progress);
 task tick(input integer interval);
 begin @(negedge clk);ts=ts+interval;sample=1;@(negedge clk);sample=0;repeat(30) @(negedge clk);end endtask
 reg signed [31:0] p=0,r=0;wire signed [15:0] iq;
 balance_pd pd(clk,rst,p,r,16'sd0,32'd1677722,32'd16777,16'd100,iq);
 initial begin
 repeat(3)@(negedge clk);rst=1;
 check_angle(8192,0,0);check_angle(8192,8192,2949120);
 check_angle(-8192,8192,8847360);check_angle(-8192,-8192,-8847360);check_angle(0,-8192,-5898240);
 @(negedge clk);zero=1;@(negedge clk);zero=0;
 repeat(8) tick(1000);
 if(!cal || busy || bad) $fatal(1,"stationary zero failed progress=%d",progress);
 tick(1000);if(rate!=0 || pitch>500 || pitch< -500) $fatal(1,"bias compensation");
 gy=108;repeat(20)tick(1000);if(rate!=-200000 || pitch> -3000) $fatal(1,"vehicle gyro integration %d %d",pitch,rate);
 tick(5000);if(cal || !bad) $fatal(1,"bad dt did not invalidate attitude");
 zero=1;@(negedge clk);zero=0;repeat(12)tick(1000);
 if(cal || progress!=0) $fatal(1,"moving gyro incorrectly calibrated");
 gy=8;repeat(8)tick(1000);if(!cal) $fatal(1,"recovery requires explicit zero");
 p=65536;repeat(8)@(negedge clk);if(iq!= -409) $fatal(1,"PD sign/units %d",iq);
 p=-655360;repeat(8)@(negedge clk);if(iq!=409) $fatal(1,"positive saturation %d",iq);
 p=655360;repeat(8)@(negedge clk);if(iq!= -409) $fatal(1,"negative saturation %d",iq);
 p=0;r=65536;repeat(8)@(negedge clk);if(iq!= -5) $fatal(1,"derivative scale %d",iq);
 // Fixed mounting: negative ax is vehicle front tilt, positive ax rear tilt.
 ax=0;ay=0;az=-8192;gy=8;zero=1;@(negedge clk);zero=0;repeat(8)tick(1000);
 ax=-2458;az=-7815;repeat(2048)tick(1000);
 if(pitch<16*65536 || pitch>19*65536)$fatal(1,"front tilt must be positive %d",pitch);
 ax=2458;repeat(2048)tick(1000);
 if(pitch> -16*65536 || pitch< -19*65536)$fatal(1,"rear tilt must be negative %d",pitch);
 gy=-32768;#1;if(attitude.gyro_signed!=32768)$fatal(1,"gyro sign extension overflow");
 $display("PASS CORDIC quadrants, bias, dt, motion rejection, PD signs and limits");$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
