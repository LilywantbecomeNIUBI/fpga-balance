`timescale 1ns/1ps
module tb_supervisor;
 reg clk=0;always #10 clk=~clk;
 reg rst=0,cv=0,configured=1,changed=0,imu=1,att=1,attbusy=0,attbad=0;
 reg [7:0] cmd=0;
 reg current=1,cbusy=0,commissioned=1,commissioning=0;reg [11:0] faults=0;
 wire active,armed,clear,cal,zero,comm,estop,can;wire [15:0] reason,gates;wire [7:0] rejected;
 wire [1:0] commission_select;
 balance_supervisor #(.ALLOW_DRIVE(1),.CLK_HZ(10000)) dut(clk,rst,cv,configured,changed,cmd,
 imu,att,attbusy,attbad,current,cbusy,commissioned,commissioning,faults,
 active,armed,clear,cal,zero,comm,estop,can,reason,gates,rejected,commission_select);
 wire obsactive,obsarmed,obscomm;
 balance_supervisor #(.ALLOW_DRIVE(0),.CLK_HZ(10000)) observe(.clk(clk),.rst_n(rst),.command_valid(cv),
 .configured(configured),.config_changed(changed),.command(cmd),.imu_ok(imu),
 .attitude_calibrated(att),.attitude_calibrating(attbusy),.attitude_bad(attbad),
 .current_calibrated(current),
 .current_calibrating(cbusy),.commissioned(commissioned),.commissioning(commissioning),.motor_faults(faults),
 .active(obsactive),.armed(obsarmed),.commission_start(obscomm));
 task send(input [7:0] c);begin @(negedge clk);cmd=c;cv=1;@(negedge clk);cv=0;end endtask
 task run_start;begin send(0);send(6);if(!armed)$fatal(1,"arm rejected gates=%h",gates);
 send(7);if(!active || armed || obsactive || obsarmed)$fatal(1,"continuous start or observe inhibit");end endtask
 initial begin
 repeat(3)@(negedge clk);rst=1;send(0);
 current=0;send(9);if(comm)$fatal(1,"uncalibrated current admitted");current=1;
 send(5);if(comm || rejected!=5)$fatal(1,"legacy automatic commissioning admitted");
 send(10);if(!comm || commission_select!=2 || obscomm)$fatal(1,"explicit M2 selection");
 send(9);if(!comm || commission_select!=1 || obscomm)$fatal(1,"explicit M1 selection");
 commissioning=1;send(10);if(comm)$fatal(1,"busy commissioning admitted");commissioning=0;
 commissioned=0;send(6);if(armed)$fatal(1,"uncommissioned runtime admitted");commissioned=1;
 run_start;send(1);if(active || !estop || reason!=1)$fatal(1,"Stop protection");
 send(6);send(7);if(active)$fatal(1,"automatic fault recovery");send(2);
 run_start;imu=0;repeat(3)@(negedge clk);if(active || reason!=8)$fatal(1,"IMU protection");imu=1;send(2);
 run_start;faults=16;repeat(3)@(negedge clk);if(active || reason!=4)$fatal(1,"motor fault");faults=0;send(2);
 run_start;repeat(1005)@(negedge clk);if(active || reason!=2)$fatal(1,"heartbeat timeout");send(2);
 run_start;
 repeat(120)begin repeat(500)@(negedge clk);send(0);if(!active || estop)$fatal(1,"continuous run timed out");end
 send(11);if(active || armed || reason!=0)$fatal(1,"normal end did not preserve non-fault state");
 run_start;if(!active)$fatal(1,"normal end required unnecessary Clear");
 send(1);if(active || reason!=1)$fatal(1,"continuous Stop failed");send(2);
 run_start;faults=2;repeat(3)@(negedge clk);if(active || reason!=4)$fatal(1,"continuous hardware fault");faults=0;send(2);
 run_start;repeat(1005)@(negedge clk);if(active || reason!=2)$fatal(1,"continuous heartbeat timeout");
 send(11);if(reason!=2)$fatal(1,"normal end cleared a real fault");
 $display("PASS supervisor physical gates, observe inhibit, IMU, driver fault, heartbeat, continuous current, manual recovery");$finish;
 end
 initial begin #3000000;$fatal(1,"timeout");end
endmodule
