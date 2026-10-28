`timescale 1ns/1ps
module tb_speed;
 reg clk=0;always #10 clk=~clk;reg rst=0,en=0,reset_loop=0;
 reg [13:0] a1=4,a2=16380;reg signed [15:0] target=0;reg [7:0] kp=100,ki=0;
 wire signed [15:0] v1,v2,trim;
 balance_speed #(.PERIOD(200)) dut(clk,rst,en,reset_loop,a1,a2,target,kp,ki,v1,v2,trim);
 task sample;begin wait(dut.ticks==199);@(posedge clk);@(negedge clk);repeat(100)@(negedge clk);#1;end endtask
 initial begin
  repeat(3)@(negedge clk);rst=1;sample();
  a1=16372;a2=12;sample();if(v1!=29 || v2!=29)$fatal(1,"forward wrap/speed units %d %d",v1,v2);
  en=1;target=100;a1=a1-16;a2=a2+16;sample();if(trim!=71)$fatal(1,"P sign/scale %d",trim);
  a1=a1+16;a2=a2-16;sample();if(v1!=-29 || v2!=-29 || trim!=129)$fatal(1,"fixed rearward directions");
  target=600;kp=255;ki=255;repeat(10)begin a1=a1-16;a2=a2+16;sample();end
  if(trim!=300 || dut.integral!=0)$fatal(1,"saturation antiwindup");
  en=0;repeat(2)@(negedge clk);if(trim || dut.integral)$fatal(1,"disable reset");
  $display("PASS speed50Hz wrap, units, encoder signs, P, trim clamp, antiwindup and disable reset");$finish;
 end
 initial begin #200000;$fatal(1,"timeout");end
endmodule
