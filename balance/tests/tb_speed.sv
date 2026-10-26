`timescale 1ns/1ps
module tb_speed;
 reg clk=0;always #10 clk=~clk;reg rst=0,en=0,reset_loop=0,r1=0,r2=0;
 reg [13:0] a1=16380,a2=16380;reg signed [15:0] target=0;reg [7:0] kp=100,ki=0;
 wire signed [15:0] v1,v2,trim;
 balance_speed #(.PERIOD(200)) dut(clk,rst,en,reset_loop,a1,a2,r1,r2,target,kp,ki,v1,v2,trim);
 task sample;begin wait(dut.ticks==199);@(posedge clk);@(negedge clk);repeat(100)@(negedge clk);#1;end endtask
 initial begin
  repeat(3)@(negedge clk);rst=1;sample();
  a1=12;a2=12;sample();if(v1!=29 || v2!=29)$fatal(1,"wrap/speed units %d %d",v1,v2);
  en=1;target=100;a1=28;a2=28;sample();if(trim!=71)$fatal(1,"P sign/scale %d",trim);
  r1=1;r2=1;a1=44;a2=44;sample();if(v1!=-29 || trim!=129)$fatal(1,"encoder direction");
  target=600;kp=255;ki=255;repeat(10)begin a1=a1+16;a2=a2+16;sample();end
  if(trim!=300 || dut.integral!=0)$fatal(1,"saturation antiwindup");
  en=0;repeat(2)@(negedge clk);if(trim || dut.integral)$fatal(1,"disable reset");
  $display("PASS speed50Hz wrap, units, encoder signs, P, trim clamp, antiwindup and disable reset");$finish;
 end
 initial begin #200000;$fatal(1,"timeout");end
endmodule
