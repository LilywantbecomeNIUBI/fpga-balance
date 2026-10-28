`timescale 1ns/1ps
// Real commissioning FSMs, accelerated frame timing, behavioral FOC only.
module tb_independent_commission;
 reg clk=0;always #10 clk=~clk;
 reg rst=0,start=0,request=0,clear=0;reg [1:0] select=0;
 reg [13:0] angle1=0,angle2=0;wire [11:0] pwm;wire [1:0] en,mask;
 wire [27:0] stimulated_angles={angle2,angle1};
 wire busy,done,failed;wire [3:0] state;
 motor_safe_drive #(.CONFIG_CONFIRMED(1),.MOTOR_MASK(3),.SELECTABLE_COMMISSION(1),.PRESERVE_CAL_ON_CLEAR(1),
 .COMM_SETTLE(8),.COMM_PREALIGN(2),.COMM_SWEEP(16),.COMM_END(8),.COMM_QUIET(2),.COMM_HANDOFF(2)) dut(
 .clk(clk),.rst_n(rst),.request_arm(request),.clear_fault(clear),.calibrate(1'b0),.estop(1'b0),
 .command_valid(1'b0),.commission_start(start),.commission_select(select),
 .iq_request_1(16'sd0),.iq_request_2(16'sd0),.drv_fault_n(2'b11),
 .adc_busy(1'b0),.adc_dout_a(1'b0),.adc_dout_b(1'b0),.enc1_do(1'b0),.enc2_do(1'b0),
 .tuning_kp(16'd0),.tuning_ki(16'd0),.pwm(pwm),.drv_en(en),
 .commissioned_mask(mask),.commissioning(busy),.commissioned(done),.commission_failed(failed),.commission_state(state));
 task pulse(input [1:0] axis);begin
  force dut.running=0;@(negedge clk);select=axis;start=1;@(negedge clk);start=0;
 end endtask
 always @(negedge clk)begin
  if(dut.commission1.state==2)angle1=dut.commission1.frames*1489/16;
  if(dut.commission1.state==3)angle1=1489;
  if(dut.commission2.state==2)angle2=dut.commission2.frames*1489/16;
  if(dut.commission2.state==3)angle2=1489;
 end
 initial begin
  repeat(3)@(negedge clk);rst=1;
  force dut.calibrated=1;force dut.feedback_valid=1;force dut.faults=0;
  force dut.phase_currents={16'sd0,-16'sd512,16'sd1024,16'sd0,-16'sd512,16'sd1024};
  force dut.mechanical_angles=stimulated_angles;
  force dut.core_en=3;force dut.core_pwm=12'hfff;
  pulse(0);repeat(3)@(negedge clk);if(busy)$fatal(1,"zero selection starts a motor");
  pulse(3);repeat(3)@(negedge clk);if(busy)$fatal(1,"dual selection starts motors");
  force dut.feedback_valid=0;pulse(2);repeat(3)@(negedge clk);
  if(!busy || dut.comm_busy!=0)$fatal(1,"pending axis was not reserved");
  pulse(1);if(dut.commission1.start_pending)$fatal(1,"other axis queued before first feedback");
  force dut.feedback_valid=1;wait(dut.comm_busy==2);force dut.running=1;#1;
  if(dut.comm_busy!=2 || en!=2 || pwm!=12'hfc0)$fatal(1,"M2-first enabled M1");
  // A different request during M2 commissioning must not queue M1.
  select=1;start=1;@(negedge clk);start=0;
  wait(!busy);#1;if(mask!=2 || done || failed || state!=6)$fatal(1,"M2 alone did not finish/preserve selected state");
  if(dut.commission1.state!=0 || dut.commission1.start_pending)$fatal(1,"M1 was queued");
  request=1;#1;if(dut.lifecycle_arm)$fatal(1,"one calibrated wheel permitted runtime");request=0;
  pulse(1);wait(busy);force dut.running=1;
  #1;if(dut.comm_busy!=1 || en!=1 || pwm!=12'h03f)$fatal(1,"M1 enabled M2");
  wait(!busy);#1;if(mask!=3 || !done || failed)$fatal(1,"M1 did not preserve M2 calibration");
  // Ordinary clear preserves both learned constants and never arms runtime.
  force dut.running=0;@(negedge clk);clear=1;repeat(4)@(negedge clk);clear=0;repeat(3)@(negedge clk);
  if(mask!=3 || !done || dut.learned_zero!={14'd1489,14'd1489} || dut.lifecycle_arm)
    $fatal(1,"clear lost completed constants or armed a motor");
  // Explicit re-calibration invalidates only the selected axis, then a failed
  // attempt cannot resurrect its old done bit on clear. Other axis survives.
  angle1=0;pulse(1);wait(dut.comm_busy==1);force dut.running=1;
  #1;if(mask!=2 || done)$fatal(1,"selected re-calibration retained stale done");
  @(negedge clk);force dut.faults=16;wait(!busy);#1;
  if(!failed || mask!=2)$fatal(1,"re-calibration failure reused old result");
  force dut.running=0;force dut.faults=0;@(negedge clk);clear=1;
  repeat(4)@(negedge clk);clear=0;repeat(3)@(negedge clk);
  if(failed || mask!=2 || dut.commission1.state!=0 || dut.comm_zero2!=1489 || dut.lifecycle_arm)
    $fatal(1,"clear restored failed result or discarded other axis");
  // FPGA reset always invalidates all calibration, even with preservation.
  rst=0;repeat(3)@(negedge clk);#1;if(mask!=0)$fatal(1,"reset preserved calibration");rst=1;
  // A failed M2 must continue reporting M2's FAIL, not M1's IDLE/COMPLETE.
  rst=0;repeat(3)@(negedge clk);rst=1;angle1=0;angle2=0;
  pulse(2);wait(busy);force dut.running=1;@(negedge clk);force dut.faults=16;
  wait(!busy);#1;if(!failed || state!=7 || dut.commission1.state!=0)$fatal(1,"M2 failure reported the wrong axis");
  $display("PASS explicit M2 first, independent M1, exclusive EN/PWM, invalid/busy requests, selected state, dual runtime gate");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
