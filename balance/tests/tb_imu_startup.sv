`timescale 1ns/1ps
// Real open-drain IMU transactions plus integrated peripheral startup order.
module tb_imu_startup;
 reg clk=0;always #10 clk=~clk;reg rst=0;
 tri1 scl,sda;wire ec1,ec2,aclk;wire [15:0] motor_pins;
 balance_top dut(.clk50m(clk),.reset_n(rst),.uart_rx(1'b1),
 .m1_pwm_ah(motor_pins[0]),.m1_pwm_al(motor_pins[1]),.m1_pwm_bh(motor_pins[2]),.m1_pwm_bl(motor_pins[3]),.m1_pwm_ch(motor_pins[4]),.m1_pwm_cl(motor_pins[5]),
 .m2_pwm_ah(motor_pins[6]),.m2_pwm_al(motor_pins[7]),.m2_pwm_bh(motor_pins[8]),.m2_pwm_bl(motor_pins[9]),.m2_pwm_ch(motor_pins[10]),.m2_pwm_cl(motor_pins[11]),
 .m1_drv_en(motor_pins[12]),.m2_drv_en(motor_pins[13]),.m1_cal(motor_pins[14]),.m2_cal(motor_pins[15]),
 .m1_fault_n(1'b1),.m2_fault_n(1'b1),.adc_busy(1'b0),.adc_dout_a(1'b0),.adc_dout_b(1'b0),
 .enc1_do(1'b0),.enc2_do(1'b0),.enc1_clk(ec1),.enc2_clk(ec2),.adc_sclk(aclk),.imu_i2c_scl(scl),.imu_i2c_sda(sda));
 // Shorten only power/startup waits; retain the production soft-reset delay.
 defparam dut.imu.POWERUP_US=100;
 defparam dut.imu.STARTUP_US=500;
 icm42688_model #(.SAMPLE_NS(1000000)) sensor(scl,sda,1'b1,8'h47,1'b0,1'b0,1'b0);
 integer encoder_edges=0;reg ever_ready=0;
 always @(posedge ec1) if(rst) begin
   if(!ever_ready) $fatal(1,"encoder clock before IMU initialization");
   encoder_edges=encoder_edges+1;
 end
 always @(posedge clk) if(rst) begin
   #1;
   if(dut.imu_ready) ever_ready=1;
   if(!ever_ready && (dut.peripheral_rst_n || ec1 || ec2)) $fatal(1,"peripherals released early");
   if(motor_pins!==0) $fatal(1,"observe motor pin enabled");
 end
 initial begin
   repeat(5) @(negedge clk);rst=1;
   wait(dut.imu_seq>=12);
   if(!dut.imu_ok || dut.imu_errors || dut.imu_invalid || !encoder_edges)
     $fatal(1,"concurrent IMU/peripheral sampling failed");
   // A later IMU fault is handled by supervisor stop, not motor reset.
   force dut.imu_ready=0;repeat(5) @(negedge clk);
   if(!dut.peripheral_rst_n || dut.imu_ok) $fatal(1,"runtime IMU fault reset motor protection");
   release dut.imu_ready;
   @(negedge clk);rst=0;repeat(3) @(negedge clk);
   if(dut.peripherals_started || dut.peripheral_rst_n) $fatal(1,"global reset did not restart sequence");
   $display("PASS IMU first startup, concurrent encoder activity, observe grounding, no runtime fault auto-reset");
   $finish;
 end
 initial begin #30000000;$fatal(1,"IMU startup timeout");end
endmodule
