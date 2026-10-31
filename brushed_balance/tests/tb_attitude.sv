`timescale 1ns/1ps
module tb_attitude;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,sample_valid=0,zero_start=0,invalidate=0;
    reg signed [15:0] ax=0,ay=0,az=-8192,gx=0,gy=0,gz=0;
    reg [31:0] commit_us=0;
    wire valid,calibrated,calibrating,bad_sample;
    wire signed [31:0] pitch,rate;
    wire [15:0] interval_us,zero_progress;
    balance_attitude #(.ZERO_LOG2(3)) dut(.clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),.zero_start(zero_start),
        .invalidate(invalidate),.filter_shift(4'd2),.ax(ax),.ay(ay),.az(az),.gx(gx),.gy(gy),.gz(gz),
        .commit_us(commit_us),.valid(valid),.calibrated(calibrated),.calibrating(calibrating),.bad_sample(bad_sample),
        .pitch(pitch),.rate(rate),.interval_us(interval_us),.zero_progress(zero_progress));
    task cycles(input integer n);begin repeat(n)@(negedge clk);end endtask
    task sample(input integer dt);begin commit_us=commit_us+dt;sample_valid=1;cycles(1);sample_valid=0;cycles(100);end endtask
    integer i;
    initial begin
        cycles(5);rst_n=1;zero_start=1;cycles(1);zero_start=0;
        for(i=0;i<8;i=i+1)sample(1000);
        if(!calibrated || calibrating || bad_sample)$fatal(1,"static calibration");
        ax=-1422;az=-8068;gy=-33;
        for(i=0;i<24;i=i+1)sample(1000);
        if(pitch<9*65536 || pitch>11*65536 || rate<60000)$fatal(1,"front tilt/gyro sign %d %d",pitch,rate);
        sample(10000);if(!bad_sample || calibrated)$fatal(1,"bad sample interval invalidates");
        invalidate=1;cycles(1);invalidate=0;ax=0;az=-8192;gy=0;
        zero_start=1;cycles(1);zero_start=0;
        for(i=0;i<8;i=i+1)sample(1000);
        if(!calibrated || bad_sample)$fatal(1,"fresh zero restores");
        $display("PASS reused IMU estimator: stationary zero, front-positive angle/rate, sample interval rejection and recalibration");$finish;
    end
endmodule
