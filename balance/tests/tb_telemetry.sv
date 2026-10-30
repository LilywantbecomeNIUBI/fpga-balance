`timescale 1ns/1ps
module tb_telemetry;
 reg clk=0;always #10 clk=~clk;reg rst=0;
 reg [1007:0] data=0;wire [1023:0] packet;wire tx,bv;wire [7:0] b;
 balance_telemetry #(.PERIOD(20000)) maker(clk,rst,data,packet);
 motor_console #(.BAUD_DIV(8),.STATUS_CYCLES(20000),.PAYLOAD_BYTES(128)) uart(
 .clk(clk),.rst_n(rst),.rx(1'b1),.status(packet),.tx(tx));
 motor_console #(.BAUD_DIV(8),.STATUS_CYCLES(1000000)) receiver(
 .clk(clk),.rst_n(rst),.rx(tx),.status(208'd0),.command_valid(bv),.command(b));
 reg [7:0] bytes[0:128];integer n=0,j;reg [15:0] crc=16'hffff;reg [7:0] checksum=0;
 function [15:0] next_crc(input [15:0] c,input [7:0] value);
 reg [15:0] v;integer i;begin v=c^{value,8'd0};for(i=0;i<8;i=i+1)v=v[15]?(v<<1)^16'h1021:v<<1;next_crc=v;end endfunction
 always @(posedge clk) if(bv) begin bytes[n]=b;n=n+1;end
 initial begin
 data[31:0]=32'h8001b6a5;data[63:32]=32'h12345678;data[223:192]=-65536;
 repeat(4)@(negedge clk);rst=1;repeat(1500)@(negedge clk);data[63:32]=32'h87654321;
 wait(n==129);#1;
 for(j=0;j<126;j=j+1)crc=next_crc(crc,bytes[j]);
 for(j=0;j<128;j=j+1)checksum=checksum^bytes[j];
 if({bytes[127],bytes[126]}!=crc || bytes[128]!=checksum)$fatal(1,"wire checksum %h %h",{bytes[127],bytes[126]},crc);
 if({bytes[7],bytes[6],bytes[5],bytes[4]}!=32'h12345678)$fatal(1,"torn telemetry snapshot");
 if({bytes[27],bytes[26],bytes[25],bytes[24]}!=-65536)$fatal(1,"signed little endian fields");
 $display("PASS 129-byte real UART frame, sequential CRC16, XOR, signed fields, atomic snapshot");$finish;
 end
 initial begin #2000000;$fatal(1,"timeout received %d",n);end
endmodule
