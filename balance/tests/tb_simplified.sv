`timescale 1ns/1ps
module tb_simplified;
reg clk=0;always #10 clk=~clk;reg rst=0;
reg arm=0,clear=0,stop=0;reg [1:0] nf=3;wire run;wire [7:0] faults;
reg soft_fault=1;
motor_drv_guard #(.SIMPLE_PROTECTION(1),.WAKE_CYCLES(2)) guard(
.clk(clk),.rst_n(rst),.arm(arm),.clear_fault(clear),.ready(1'b1),.estop(stop),.fault_n(nf),
.sensor_fault(soft_fault),.overcurrent(soft_fault),.sync_fault(soft_fault),.pwm_in(12'h555),.running(run),.faults(faults));
reg valid=0;reg [13:0] angle=0;reg [31:0] ct=0,et=0;wire sf,tf,av;
motor_measurement_angle #(.CHECKS_ENABLED(0),.MAX_STEP(512),.MAX_WINDOW_TICKS(512)) measure(
.clk(clk),.rst_n(rst),.valid(valid),.mechanical(angle),.current_time(ct),.encoder_time(et),.speed_fault(sf),.timing_fault(tf),.aligned_valid(av));
reg cs=0,cc=0;reg [13:0] ca=0;wire done;wire [3:0] state;wire [13:0] zero;
motor_commission #(.RELAXED_ACCEPTANCE(1),.PRESERVE_CAL_ON_CLEAR(1),.SETTLE_FRAMES(8),.SWEEP_FRAMES(16),.END_FRAMES(8),.QUIET_FRAMES(2),.HANDOFF_CYCLES(2)) commission(
.clk(clk),.rst_n(rst),.start(cs),.clear_fault(cc),.calibrated(1'b1),.feedback_valid(1'b1),.running(1'b1),.mechanical(ca),
.ia(-16'sd3000),.ib(16'sd2500),.faults(12'd0),.done(done),.zero(zero),.state(state));
always @(negedge clk)begin if(state==2)ca=commission.frames*600/16;if(state==3)ca=600;end
reg req=0,cmd=0;wire signed [15:0] iq;
motor_command_guard #(.IQ_LIMIT(4915),.SLEW_PER_FRAME(4915),.CMD_TIMEOUT(1000),.MAX_RUN_CYCLES(0)) command_guard(
.clk(clk),.rst_n(rst),.request_arm(req),.clear_fault(1'b0),.command_valid(cmd),.frame_valid(1'b1),
.iq_request_1(16'sd7000),.iq_request_2(-16'sd7000),.iq_1(iq));
reg sup_done=0,scv=0,imu=1,attbad=0;reg [7:0] scmd=0;
wire sa,sarm;wire [15:0] reason;
balance_supervisor #(.SIMPLE_PROTECTION(1),.ALLOW_DRIVE(1),.CLK_HZ(10000)) supervisor(
.clk(clk),.rst_n(rst),.command_valid(scv),.configured(1'b1),.config_changed(1'b0),.command(scmd),
.imu_ok(imu),.attitude_calibrated(1'b1),.attitude_calibrating(1'b0),.attitude_bad(attbad),
.current_calibrated(1'b1),.current_calibrating(1'b0),
.commissioned(1'b1),.commissioning(1'b0),.motor_faults(12'd0),.active(sa),.armed(sarm),.stop_reason(reason));
task send(input [7:0] c);begin @(negedge clk);scmd=c;scv=1;@(negedge clk);scv=0;end endtask
initial begin
wait(rst);repeat(4)@(negedge clk);send(0);send(6);send(7);#1;if(!sa)$fatal(1,"minimal supervisor start");
imu=0;attbad=1;repeat(10)@(negedge clk);#1;if(!sa || reason!=0)$fatal(1,"removed IMU runtime fault still trips");
imu=1;attbad=0;send(2);send(0);send(6);send(7);repeat(1010)@(negedge clk);
#1;if(sa || reason!=2)$fatal(1,"heartbeat timeout missing");
sup_done=1;
end
initial begin
repeat(3)@(negedge clk);rst=1;repeat(4)@(negedge clk);arm=1;cs=1;cmd=1;
@(negedge clk);cs=0;cmd=0;req=1;
repeat(8)@(negedge clk);#1;if(!run || faults!=0)$fatal(1,"software faults still stop");
if(iq!=4915)$fatal(1,"Iq hard limit is not 1.2A");
valid=1;@(negedge clk);valid=0;wait(av);@(negedge clk);
angle=1000;ct=999999;et=9999;valid=1;@(negedge clk);valid=0;wait(av);#1;
if(sf || tf)$fatal(1,"speed/timestamp check still trips");
wait(done);#1;if(zero!=600)$fatal(1,"relaxed commissioning result");
@(negedge clk);cc=1;@(negedge clk);cc=0;#1;if(!done)$fatal(1,"clear discarded electrical calibration");
nf=2;#1;if(run)$fatal(1,"M1 hardware fault did not kill asynchronously");
repeat(2)@(negedge clk);#1;if(faults!=2)$fatal(1,"unexpected chained fault bits %h",faults);
arm=0;nf=3;repeat(4)@(negedge clk);clear=1;repeat(2)@(negedge clk);clear=0;arm=1;
repeat(8)@(negedge clk);#1;if(!run)$fatal(1,"did not rearm after clear");
nf=1;#1;if(run)$fatal(1,"M2 hardware fault did not kill");repeat(2)@(negedge clk);
if(faults!=4)$fatal(1,"M2 fault identity %h",faults);
arm=0;nf=3;repeat(4)@(negedge clk);clear=1;repeat(2)@(negedge clk);clear=0;arm=1;
repeat(8)@(negedge clk);stop=1;#1;if(run)$fatal(1,"Stop did not kill");
repeat(2)@(negedge clk);if(faults!=1)$fatal(1,"Stop code");
wait(sup_done);$display("PASS simplified supervisor heartbeat, faults, hardware M1/M2, Stop, disabled speed/timing, 1.2A clamp, relaxed commissioning and clear preservation");$finish;
end
initial begin #100000;$fatal(1,"timeout");end
endmodule
