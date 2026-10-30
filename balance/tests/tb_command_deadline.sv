`timescale 1ns/1ps
module tb_command_deadline;
reg clk=0;always #10 clk=~clk;reg rst=0,req=0,clear=0,valid=0;wire arm,one;integer i;
motor_command_guard #(.CMD_TIMEOUT(37),.MAX_RUN_CYCLES(0)) dut(.clk(clk),.rst_n(rst),.request_arm(req),.clear_fault(clear),.command_valid(valid),.frame_valid(1'b1),.iq_request_1(16'sd100),.iq_request_2(-16'sd100),.arm(arm));
motor_command_guard #(.CMD_TIMEOUT(1),.MAX_RUN_CYCLES(0)) edgecase(.clk(clk),.rst_n(rst),.request_arm(req),.clear_fault(clear),.command_valid(valid),.frame_valid(1'b1),.iq_request_1(16'sd100),.iq_request_2(-16'sd100),.arm(one));
always @(posedge clk)begin #1;if(rst)begin
 if(arm !== (req && dut.seen_command && dut.command_age<37 && dut.faults==0))$fatal(1,"freshness changed original deadline");
 if(one !== (req && edgecase.seen_command && edgecase.command_age<1 && edgecase.faults==0))$fatal(1,"single-clock deadline changed");
end end
initial begin repeat(3)@(negedge clk);rst=1;
for(i=0;i<1000;i=i+1)begin @(negedge clk);req=(i%100)>3;clear=(i%100)==1;valid=(i%100)==2 || (i%100)==20 || (i%100)==39;end
$display("PASS exact command expiry clock, refresh, clear, fault and one-clock boundary");$finish;end
endmodule
