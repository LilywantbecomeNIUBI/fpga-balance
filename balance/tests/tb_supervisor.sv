`timescale 1ns/1ps
module tb_supervisor;
 reg clk=0;always #10 clk=~clk;
 reg rst=0,cv=0,configured=1,changed=0,imu=1,att=1,attbusy=0,attbad=0;
 reg [7:0] cmd=0,flags=8'he0;reg signed [31:0] pitch=0;
 reg [15:0] duration=1000;reg current=1,cbusy=0,commissioned=1,commissioning=0;reg [11:0] faults=0;
 wire active,armed,clear,cal,zero,comm,estop,can;wire [15:0] reason,gates;wire [7:0] rejected;
 balance_supervisor #(.ALLOW_DRIVE(1),.CLK_HZ(10000)) dut(clk,rst,cv,configured,changed,cmd,flags,
 imu,att,attbusy,attbad,pitch,16'd1500,16'd300,duration,current,cbusy,commissioned,commissioning,faults,
 active,armed,clear,cal,zero,comm,estop,can,reason,gates,rejected);
 wire obsactive,obsarmed,obscomm;
 balance_supervisor #(.ALLOW_DRIVE(0),.CLK_HZ(10000)) observe(.clk(clk),.rst_n(rst),.command_valid(cv),
 .configured(configured),.config_changed(changed),.command(cmd),.flags(flags),.imu_ok(imu),
 .attitude_calibrated(att),.attitude_calibrating(attbusy),.attitude_bad(attbad),.pitch(pitch),
 .cutoff_cdeg(16'd1500),.start_cdeg(16'd300),.duration_ms(duration),.current_calibrated(current),
 .current_calibrating(cbusy),.commissioned(commissioned),.commissioning(commissioning),.motor_faults(faults),
 .active(obsactive),.armed(obsarmed),.commission_start(obscomm));
 task send(input [7:0] c);begin @(negedge clk);cmd=c;cv=1;@(negedge clk);cv=0;end endtask
 task run_start;begin send(0);send(6);if(!armed)$fatal(1,"arm rejected gates=%h",gates);
 send(7);if(!active || armed || obsactive || obsarmed)$fatal(1,"one-shot start or observe inhibit");end endtask
 initial begin
 repeat(3)@(negedge clk);rst=1;send(0);
 flags=8'h60;send(6);send(7);if(active || armed)$fatal(1,"unaccepted M2 admitted");
 send(5);if(comm)$fatal(1,"unaccepted commissioning admitted");flags=8'he0;
 pitch=4*65536;send(6);if(armed)$fatal(1,"start tilt gate");pitch=0;
 run_start;pitch=16*65536;repeat(3)@(negedge clk);
 if(active || !estop || reason!=16'h10)$fatal(1,"tilt protection");
 pitch=0;send(6);send(7);if(active)$fatal(1,"automatic fault recovery");send(2);
 run_start;imu=0;repeat(3)@(negedge clk);if(active || reason!=8)$fatal(1,"IMU protection");imu=1;send(2);
 run_start;faults=16;repeat(3)@(negedge clk);if(active || reason!=4)$fatal(1,"motor fault");faults=0;send(2);
 run_start;repeat(1005)@(negedge clk);if(active || reason!=2)$fatal(1,"heartbeat timeout");send(2);
 duration=100;run_start;repeat(500)@(negedge clk);send(0);repeat(505)@(negedge clk);
 if(active || armed || estop)$fatal(1,"bounded normal completion");
 run_start;send(1);if(active || reason!=1)$fatal(1,"explicit stop");
 $display("PASS supervisor M2 gate, observe inhibit, tilt, IMU, driver fault, heartbeat, bounded run, manual recovery");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
