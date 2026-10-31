`timescale 1ns/1ps
module tb_core;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0,left_enc_a=0,left_enc_b=0,right_enc_a=0,right_enc_b=0;
    reg command_valid=0;reg [7:0] opcode=0,sequence_id=0;reg [319:0] payload=0;
    reg imu_healthy=1,attitude_valid=1,attitude_calibrated=0,attitude_calibrating=0;
    reg signed [31:0] pitch=0,rate=0;
    wire zero_start;wire [3:0] filter_shift;
    wire left_in1,left_in2,right_in1,right_in2,armed,config_valid;
    wire [7:0] mode,last_sequence,config_sequence,stop_reason;
    wire [15:0] faults,rejected;
    wire signed [31:0] left_position,right_position,left_velocity,right_velocity,speed_trim;
    wire signed [15:0] left_applied,right_applied;wire [31:0] left_invalid,right_invalid;
    bb_core #(.CLK_HZ(1000000),.DRIVE_ENABLE(1),.WATCHDOG_MS(20)) dut(.*);
    wire obs_l1,obs_l2,obs_r1,obs_r2;
    bb_core #(.CLK_HZ(1000000),.DRIVE_ENABLE(0),.WATCHDOG_MS(20)) observe(
        .clk(clk),.reset_n(reset_n),.left_enc_a(left_enc_a),.left_enc_b(left_enc_b),.right_enc_a(right_enc_a),.right_enc_b(right_enc_b),
        .command_valid(command_valid),.opcode(opcode),.sequence_id(sequence_id),.payload(payload),
        .imu_healthy(imu_healthy),.attitude_valid(attitude_valid),.attitude_calibrated(attitude_calibrated),.attitude_calibrating(attitude_calibrating),
        .pitch(pitch),.rate(rate),.left_in1(obs_l1),.left_in2(obs_l2),.right_in1(obs_r1),.right_in2(obs_r2));
    reg [319:0] cfg;
    integer i;reg [15:0] rejected_before;
    task cycles(input integer n);begin repeat(n)@(negedge clk);end endtask
    task send(input [7:0] op,input [319:0] data);begin
        opcode=op;sequence_id=sequence_id+1;payload=data;command_valid=1;cycles(1);command_valid=0;cycles(2);
    end endtask
    task config_mode(input [7:0] m,input [7:0] f);begin
        cfg=0;cfg[0+:8]=m;cfg[8+:8]=f;cfg[16+:8]=m<3?1:3;cfg[24+:8]=6;
        cfg[32+:16]=100;cfg[48+:16]=5120;cfg[64+:16]=256;
        cfg[80+:16]=256;cfg[160+:16]=500;cfg[176+:16]=3500;cfg[192+:16]=300;
        cfg[208+:16]=m<3?100:0;send(2,cfg);
    end endtask
    always @(negedge clk)if(reset_n && (obs_l1||obs_l2||obs_r1||obs_r2))$fatal(1,"observe physical output");
    initial begin
        cycles(5);reset_n=1;cycles(5);if(armed || faults!=1)$fatal(1,"power-on locked");
        send(1,0);config_mode(1,0);send(4,0);if(!armed)$fatal(1,"PWM bench arm");
        send(5,320'd50);cycles(1800);
        if(left_applied!=50 || right_applied!=0 || right_in1 || right_in2)$fatal(1,"one wheel isolation");
        rejected_before=rejected;send(5,320'd200);if(rejected!=rejected_before+1 || left_applied!=50)$fatal(1,"oversized PWM rejected atomically");
        rejected_before=rejected;send(2,cfg);if(rejected!=rejected_before+1 || !armed)$fatal(1,"running configuration mutation");
        // A replay is rejected and does not renew the watchdog.
        opcode=6;payload=0;sequence_id=last_sequence;command_valid=1;cycles(1);command_valid=0;cycles(21000);
        if(armed || !(faults&2) || left_in1 || left_in2)$fatal(1,"watchdog/replay stop");
        send(1,0);config_mode(1,0);send(4,0);send(5,320'd30);
        for(i=0;i<21;i=i+1)begin cycles(5000);send(6,0);end
        if(armed || faults!=0 || stop_reason!=3)$fatal(1,"FPGA bench deadline");
        config_mode(3,1);send(4,0);if(armed)$fatal(1,"uncalibrated balance start");
        attitude_calibrated=1;pitch=6*65536;send(4,0);if(armed)$fatal(1,"start angle guard");
        pitch=2*65536;send(4,0);cycles(20);
        if(!armed || left_applied!=-40 || right_applied!=40)$fatal(1,"balance direct PWM and independent physical polarity %d %d",left_applied,right_applied);
        pitch=40*65536;cycles(2);if(armed || !(faults&8) || left_in1 || right_in2)$fatal(1,"fall stop");
        pitch=0;send(1,0);cycles(10);if(armed)$fatal(1,"clear cannot auto restart");
        send(4,0);imu_healthy=0;cycles(2);if(armed || !(faults&4))$fatal(1,"IMU stale stop");
        imu_healthy=1;send(1,0);send(4,0);attitude_valid=0;cycles(10005);
        if(armed || !(faults&4))$fatal(1,"estimator update stale stop");
        attitude_valid=1;send(1,0);config_mode(1,0);send(4,0);send(5,320'd50);
        opcode=0;sequence_id=last_sequence;payload=~320'b0;command_valid=1;cycles(1);command_valid=0;cycles(2);
        if(armed || !(faults&1) || left_in1 || left_in2)$fatal(1,"STOP must bypass sequence and payload policies");
        $display("PASS lifecycle: locked startup, one-wheel isolation, command validation, replay watchdog, deadline, calibrated/start gates, direct PD polarity, fall/stale/STOP and no restart");$finish;
    end
    initial begin #4000000;$fatal(1,"core timeout");end
endmodule
