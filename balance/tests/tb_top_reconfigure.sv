`timescale 1ns/1ps
module tb_top_reconfigure;
 reg clk=0;always #10 clk=~clk;reg rst=0,sv=0,z=0,changed=0,clear=0;
 reg [31:0] ts=0;reg [255:0] cfg=0;tri1 scl,sda;
 balance_top dut(.clk50m(clk),.reset_n(rst),.uart_rx(1'b1),.m1_fault_n(1'b1),.m2_fault_n(1'b1),
 .adc_busy(1'b0),.adc_dout_a(1'b0),.adc_dout_b(1'b0),.enc1_do(1'b0),.enc2_do(1'b0),.imu_i2c_scl(scl),.imu_i2c_sda(sda));
 defparam dut.attitude.ZERO_LOG2=3;
 task sample;begin
  @(negedge clk);ts=ts+1000;sv=1;@(negedge clk);sv=0;repeat(100)@(negedge clk);
 end endtask
 integer i;reg signed [31:0] saved_bias,saved_angle;
 initial begin
  cfg[215:208]=8;repeat(4)@(negedge clk);rst=1;repeat(5)@(negedge clk);
  force dut.peripheral_rst_n=1;force dut.cfg=cfg;force dut.sv=sv;force dut.commit_us=ts;
  force dut.ax=0;force dut.ay=0;force dut.az=-8192;force dut.gx=0;force dut.gy=8;force dut.gz=0;
  force dut.changed=changed;force dut.clear_fault=clear;force dut.zero_start=z;
  force dut.drive.core.join_valid=0;force dut.drive.core.cal_start=0;
  @(negedge clk);z=1;@(negedge clk);z=0;
  repeat(8)sample;
  if(!dut.att_cal || dut.att_busy)$fatal(1,"attitude zero did not complete");
  saved_bias=dut.attitude.bias;saved_angle=dut.attitude.zero_angle;
  dut.drive.core.currents.calibrated=1;
  dut.drive.commission1.state=6;dut.drive.commission1.done=1;dut.drive.commission1.zero=1234;dut.drive.commission1.reverse=1;
  dut.drive.commission2.state=6;dut.drive.commission2.done=1;dut.drive.commission2.zero=4321;dut.drive.commission2.reverse=0;
  for(i=0;i<3;i=i+1)begin
   @(negedge clk);cfg[63:32]=1000+i;cfg[95:64]=200+i;cfg[207:192]=i==0 ? 0 : 500;
   changed=1;@(negedge clk);changed=0;sample;
   if(!dut.att_cal || !dut.current_cal || dut.comm_mask!==3)$fatal(1,"apply discarded calibration");
   if(dut.attitude.bias!==saved_bias || dut.attitude.zero_angle!==saved_angle)$fatal(1,"apply changed attitude reference");
   if(dut.learned_zero!=={14'd4321,14'd1234} || dut.learned_reverse!==1)$fatal(1,"apply changed electrical calibration");
  end
  @(negedge clk);clear=1;@(negedge clk);clear=0;repeat(5)@(negedge clk);
  if(dut.att_cal || dut.current_cal || dut.comm_mask!==3)$fatal(1,"explicit Clear semantics changed");
  $display("PASS repeated parameter applies preserve attitude/current/electrical calibration; explicit Clear invalidates zeros and retains electrical");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
