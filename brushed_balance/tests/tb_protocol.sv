`timescale 1ns/1ps
module tb_protocol;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0,byte_valid=0,framing_error=0;reg [7:0] byte_data=0;
    wire command_valid;wire [7:0] opcode,sequence_id;wire [319:0] payload;wire [15:0] bad_frames;
    bb_protocol #(.CLK_HZ(1000000)) dut(.*);
    reg [7:0] bytes[0:191];integer n,count=0;
    task cycles(input integer k);begin repeat(k)@(negedge clk);end endtask
    task put(input [7:0] value);begin byte_data=value;byte_valid=1;cycles(1);byte_valid=0;cycles(2);end endtask
    always @(negedge clk)if(command_valid)begin
        if(sequence_id!=count+1)$fatal(1,"sequence decoded");
        if(count==0 && (opcode!=2 || payload[0+:8]!=3 || payload[48+:16]!=5120))$fatal(1,"Python to RTL config fields");
        if(count==2 && (opcode!=5 || payload[32+:16]!=256))$fatal(1,"Python to RTL target field");
        count=count+1;
    end
    initial begin
        $readmemh("build/tests/commands.hex",bytes);cycles(4);reset_n=1;
        put(8'hb6);put(8'hb6);put(8'h00); // header resynchronization
        for(n=0;n<192;n=n+1)put(bytes[n]);
        if(count!=4 || bad_frames!=0)$fatal(1,"valid frames");
        for(n=0;n<48;n=n+1)put(n==20 ? bytes[n]^8'h1 : bytes[n]);
        if(count!=4 || bad_frames!=1)$fatal(1,"corrupt frame rejected");
        put(8'hb6);put(8'h6b);cycles(20005);if(bad_frames!=2)$fatal(1,"truncated frame timeout");
        framing_error=1;cycles(1);framing_error=0;cycles(2);if(bad_frames!=3)$fatal(1,"UART framing error");
        $display("PASS Python-to-RTL command CRC/fields, header resync, corruption, partial timeout and framing error");$finish;
    end
endmodule
