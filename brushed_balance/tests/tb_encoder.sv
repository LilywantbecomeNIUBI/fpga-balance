`timescale 1ns/1ps
module tb_encoder;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0,a=0,b=0,tick=0,reverse=0;
    wire signed [31:0] position,velocity;wire [31:0] invalid_count;
    bb_encoder dut(.*);
    task cycles(input integer n);begin repeat(n)@(negedge clk);end endtask
    task phase(input [1:0] ab);begin {a,b}=ab;cycles(30);end endtask
    integer i;
    initial begin
        cycles(4);reset_n=1;cycles(30);
        for(i=0;i<250;i=i+1)begin phase(1);phase(3);phase(2);phase(0);end
        if(position!=1000 || invalid_count!=0)$fatal(1,"AB x4 full cycle count");
        tick=1;cycles(1);tick=0;cycles(1);if(velocity!=1000)$fatal(1,"window count");
        for(i=0;i<10;i=i+1)begin phase(2);phase(3);phase(1);phase(0);end
        if(position!=960)$fatal(1,"reverse rotation");
        reverse=1;phase(1);phase(3);phase(2);phase(0);if(position!=956)$fatal(1,"configured polarity");
        {a,b}=3;cycles(2);{a,b}=0;cycles(30);if(position!=956)$fatal(1,"glitch filter");
        phase(3);if(position!=956 || invalid_count!=1)$fatal(1,"diagonal must not invent motion");
        phase(0);if(position!=956 || invalid_count!=2)$fatal(1,"second diagonal");
        $display("PASS standard AB x4: 1000 edges, both directions, polarity, glitch rejection, ambiguous diagonal accounting");$finish;
    end
endmodule
