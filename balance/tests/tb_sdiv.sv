`timescale 1ns/1ps
module tb_sdiv;
 reg clk=0;always #10 clk=~clk;reg rst=0,start=0;reg signed [31:0] n=0;reg [15:0] d=1;
 wire busy,valid;wire signed [31:0] q;
 balance_sdiv dut(clk,rst,start,n,d,busy,valid,q);
 task check(input signed [31:0] value,input [15:0] divisor);integer cycles;begin
  @(negedge clk);n=value;d=divisor;start=1;@(negedge clk);start=0;cycles=0;
  while(!valid)begin @(negedge clk);cycles=cycles+1;if(cycles>34)$fatal(1,"division deadline");end
  if(q!==value/$signed({1'b0,divisor}))$fatal(1,"division mismatch %d/%d = %d",value,divisor,q);
  @(negedge clk);if(valid)$fatal(1,"valid not one cycle");
 end endtask
 integer i;
 initial begin
  repeat(3)@(negedge clk);rst=1;
  check(0,100);check(-1,100);check(2147483647,100);check(-2147483647,5000);check(-2147483648,1);
  for(i=-50;i<=50;i=i+1)begin check(i*7321,100);check(i*12579,5000);end
  $display("PASS sequential signed division: truncation, extremes, bounded latency, one-cycle valid");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
