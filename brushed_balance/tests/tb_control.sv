`timescale 1ns/1ps
module tb_control;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0,enable=0,reverse=0,tick=0;
    reg signed [31:0] pitch=0,rate=0,target=0;
    reg [15:0] kp=5120,kd=1280,pwm_limit=100;
    wire signed [15:0] demand;
    bb_pd pd(.*);
    reg signed [31:0] left_velocity=0,right_velocity=0;
    reg signed [15:0] target_rpm_q8=0;
    reg [15:0] skp=6554,ki_tick=0,limit_cdeg=300;
    wire signed [31:0] trim_q16;
    bb_speed speed(.clk(clk),.reset_n(reset_n),.tick(tick),.enable(enable),.left_velocity(left_velocity),
        .right_velocity(right_velocity),.target_rpm_q8(target_rpm_q8),.kp(skp),.ki_tick(ki_tick),.limit_cdeg(limit_cdeg),.trim_q16(trim_q16));
    task cycles(input integer n);begin repeat(n)@(negedge clk);end endtask
    task update_speed;begin tick=1;cycles(1);tick=0;cycles(12);end endtask
    integer i;
    initial begin
        cycles(5);reset_n=1;enable=1;pitch=2*65536;rate=-65536;cycles(15);
        if(demand!=35)$fatal(1,"PD unit/sign expected 35 got %d",demand);
        reverse=1;cycles(15);if(demand!=-35)$fatal(1,"PD reverse");
        reverse=0;pwm_limit=10;cycles(15);if(demand!=10)$fatal(1,"PD cap");
        pwm_limit=100;target=65536;cycles(15);if(demand!=15)$fatal(1,"target-angle sign");
        left_velocity=10;right_velocity=10;target_rpm_q8=0;update_speed();
        if(trim_q16> -6500 || trim_q16< -6600)$fatal(1,"GMR one rpm negative feedback %d",trim_q16);
        left_velocity=0;right_velocity=0;target_rpm_q8=30720;limit_cdeg=100;
        for(i=0;i<20;i=i+1)update_speed();
        if(trim_q16<65530 || trim_q16>65536)$fatal(1,"outer angle cap %d",trim_q16);
        target_rpm_q8=0;update_speed();if(trim_q16!=0)$fatal(1,"antiwindup should not retain saturated P");
        skp=0;ki_tick=1311;target_rpm_q8=256;
        for(i=0;i<5;i=i+1)update_speed();
        if(trim_q16<6500 || trim_q16>6600)$fatal(1,"outer integral units %d",trim_q16);
        enable=0;cycles(1);if(trim_q16!=0 || demand!=0)$fatal(1,"disable clears controllers");
        $display("PASS PD and outer PI: physical units/signs, trim, polarity, saturation, anti-windup, integral time and reset");$finish;
    end
endmodule
