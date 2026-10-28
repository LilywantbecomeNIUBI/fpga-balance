`timescale 1ns/1ps
module tb_clear_compat;
reg clk=0;always #10 clk=~clk;
reg rst=0,start=0,clear=0;reg [13:0] angle=0;
wire [3:0] oldstate,newstate;wire olddone,newdone,oldarm,newarm;
wire [13:0] oldzero,newzero;
motor_commission #(.SETTLE_FRAMES(8),.SWEEP_FRAMES(16),.END_FRAMES(8),.QUIET_FRAMES(2),.HANDOFF_CYCLES(2)) legacy(
.clk(clk),.rst_n(rst),.start(start),.clear_fault(clear),.calibrated(1'b1),.feedback_valid(1'b1),.running(1'b1),.mechanical(angle),.ia(16'sd1024),.ib(-16'sd512),.faults(12'd0),.done(olddone),.arm(oldarm),.zero(oldzero),.state(oldstate));
motor_commission #(.PRESERVE_CAL_ON_CLEAR(1),.SETTLE_FRAMES(8),.SWEEP_FRAMES(16),.END_FRAMES(8),.QUIET_FRAMES(2),.HANDOFF_CYCLES(2)) integrated(
.clk(clk),.rst_n(rst),.start(start),.clear_fault(clear),.calibrated(1'b1),.feedback_valid(1'b1),.running(1'b1),.mechanical(angle),.ia(16'sd1024),.ib(-16'sd512),.faults(12'd0),.done(newdone),.arm(newarm),.zero(newzero),.state(newstate));
always @(negedge clk)begin
 if(oldstate==2)angle=legacy.frames*1489/16;
 if(oldstate==3)angle=1489;
end
initial begin
 repeat(3)@(negedge clk);rst=1;@(negedge clk);start=1;@(negedge clk);start=0;
 wait(olddone && newdone);#1;if(oldzero!=1489 || newzero!=1489)$fatal(1,"bad initial calibration");
 @(negedge clk);clear=1;repeat(3)@(negedge clk);clear=0;#1;
 if(olddone || oldzero!=0 || oldstate!=0)$fatal(1,"legacy clear changed");
 if(!newdone || newzero!=1489 || newstate!=6 || newarm || oldarm)$fatal(1,"integrated preservation/arm");
 rst=0;#1;if(olddone || newdone || newzero!=0)$fatal(1,"reset did not invalidate");
 $display("PASS legacy clear invalidates, integrated clear preserves learned result without arm, reset invalidates both");$finish;
end
initial begin #100000;$fatal(1,"timeout");end
endmodule
