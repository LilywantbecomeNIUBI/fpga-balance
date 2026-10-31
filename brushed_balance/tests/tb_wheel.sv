`timescale 1ns/1ps
module tb_wheel;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0,tick=0,enable=0,motor_reverse=0;
    reg signed [15:0] target=100;
    reg signed [31:0] velocity=0;
    reg [15:0] kp=4096,ki=1024,pwm_limit=40;
    wire signed [15:0] applied;
    bb_wheel_pi #(.REVERSE_TICKS(2)) dut(.*);
    task cycles(input integer n);begin repeat(n)@(negedge clk);end endtask
    task update;begin tick=1;cycles(1);tick=0;cycles(10);end endtask
    integer i;
    initial begin
        cycles(5);reset_n=1;enable=1;
        for(i=0;i<10;i=i+1)update();
        if(applied!=40 || dut.integral>10240)$fatal(1,"configured output and integral cap");
        target=0;for(i=0;i<5;i=i+1)update();
        if(applied!=0 || dut.integral!=0)$fatal(1,"zero target resets integral and ramps to coast");
        target=-100;for(i=0;i<8;i=i+1)update();
        if(applied!=-40)$fatal(1,"negative target");
        enable=0;cycles(1);if(applied!=0)$fatal(1,"disable bypasses ramp");
        $display("PASS bench PI: configured cap/anti-windup, zero target, signed reversal, immediate disable");$finish;
    end
endmodule
