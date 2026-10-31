`timescale 1ns/1ps
module tb_top_m2;
    reg clk50m=0;always #10 clk50m=~clk50m;
    reg reset_n=0;reg [1:0] l=0,r=0;
    tri1 imu_i2c_scl,imu_i2c_sda;
    wire left_in1,left_in2,right_in1,right_in2,uart_tx,legacy_m1_disable,legacy_m1_cal_disabled;
    wire [5:0] legacy_m1_pwm_disabled;wire [7:0] led;
    brushed_balance_top dut(.clk50m(clk50m),.reset_n(reset_n),.uart_rx(1'b1),.imu_i2c_scl(imu_i2c_scl),.imu_i2c_sda(imu_i2c_sda),
        .left_enc_a(l[1]),.left_enc_b(l[0]),.right_enc_a(r[1]),.right_enc_b(r[0]),
        .left_in1(left_in1),.left_in2(left_in2),.right_in1(right_in1),.right_in2(right_in2),.uart_tx(uart_tx),
        .legacy_m1_disable(legacy_m1_disable),.legacy_m1_pwm_disabled(legacy_m1_pwm_disabled),
        .legacy_m1_cal_disabled(legacy_m1_cal_disabled),.led(led));
    task cycles(input integer n);begin repeat(n)@(negedge clk50m);end endtask
    task left_phase(input [1:0] v);begin l=v;cycles(30);end endtask
    task right_phase(input [1:0] v);begin r=v;cycles(30);end endtask
    integer i;
    always @(negedge clk50m)if(reset_n && (left_in1||left_in2||right_in1||right_in2||legacy_m1_disable||legacy_m1_cal_disabled||legacy_m1_pwm_disabled!=0))
        $fatal(1,"observation and old M1 outputs must stay low");
    initial begin
        cycles(5);reset_n=1;cycles(50);
        for(i=0;i<4;i=i+1)begin left_phase(1);left_phase(3);left_phase(2);left_phase(0);end
        for(i=0;i<3;i=i+1)begin right_phase(2);right_phase(3);right_phase(1);right_phase(0);end
        if(dut.core.left_position!=16 || dut.core.right_position!=-12)$fatal(1,"top-level encoder inputs blocked or crossed");
        if(dut.core.left_invalid || dut.core.right_invalid)$fatal(1,"clean top-level quadrature");
        if(dut.telemetry.status_flags[7]!=1)$fatal(1,"M2 pin profile identity missing");
        $display("PASS M2 board top: all four encoder inputs reach counters, independent directions, profile identity, disabled observation/M1 outputs");$finish;
    end
endmodule
