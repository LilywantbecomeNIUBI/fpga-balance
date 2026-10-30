`timescale 1ns/1ps
// Integration of real commissioning FSM and both output masks. The plant and
// core-ready/PWM signals are controlled stimuli, not a physical FOC model.
module tb_top_commission;
 reg clk=0;always #10 clk=~clk;reg rst=0,start=0;
 reg [1:0] select=0;reg [255:0] cfg=0;
 reg [13:0] angle1=0,angle2=0;
 wire [27:0] angles={angle2,angle1};
 wire [11:0] pwm;wire en1,en2;tri1 scl,sda;
 balance_top #(.ALLOW_DRIVE(1)) dut(.clk50m(clk),.reset_n(rst),.uart_rx(1'b1),
 .m1_pwm_ah(pwm[0]),.m1_pwm_al(pwm[1]),.m1_pwm_bh(pwm[2]),.m1_pwm_bl(pwm[3]),.m1_pwm_ch(pwm[4]),.m1_pwm_cl(pwm[5]),
 .m2_pwm_ah(pwm[6]),.m2_pwm_al(pwm[7]),.m2_pwm_bh(pwm[8]),.m2_pwm_bl(pwm[9]),.m2_pwm_ch(pwm[10]),.m2_pwm_cl(pwm[11]),
 .m1_drv_en(en1),.m2_drv_en(en2),.m1_fault_n(1'b1),.m2_fault_n(1'b1),
 .adc_busy(1'b0),.adc_dout_a(1'b0),.adc_dout_b(1'b0),.enc1_do(1'b0),.enc2_do(1'b0),.imu_i2c_scl(scl),.imu_i2c_sda(sda));
 defparam dut.drive.COMM_SETTLE=8,dut.drive.COMM_PREALIGN=2,
          dut.drive.COMM_SWEEP=16,dut.drive.COMM_END=8,
          dut.drive.COMM_QUIET=2,dut.drive.COMM_HANDOFF=2;
 always @(negedge clk)begin
  if(dut.drive.commission1.state==2)angle1=dut.drive.commission1.frames*1489/16;
  if(dut.drive.commission1.state==3)angle1=1489;
  if(dut.drive.commission2.state==2)angle2=dut.drive.commission2.frames*1489/16;
  if(dut.drive.commission2.state==3)angle2=1489;
 end
 task commission(input [1:0] axis);
 integer n;
 begin
  force dut.drive.running=0;@(negedge clk);select=axis;start=1;
  @(negedge clk);start=0;force dut.drive.running=1;
  for(n=0;n<150;n=n+1)begin
   @(negedge clk);#1;
   if(dut.drive.commission_arm)begin
    if(dut.drive.core.voltage_limit!==8192 || dut.drive.core.q_voltage_limit!==8192)$fatal(1,"commission voltage ceiling is not 0.25");
    if(dut.drive.commands.target_1!==1434 || dut.drive.commands.target_2!==1434)$fatal(1,"commission Id target is not 0.35A");
    if(dut.drive.core.iq_ref_1!==0 || dut.drive.core.iq_ref_2!==0)$fatal(1,"commission added nonzero Iq");
    if(axis==1 && dut.drive.core.id_ref_2!==0)$fatal(1,"M1 commission excites M2 Id");
    if(axis==2 && dut.drive.core.id_ref_1!==0)$fatal(1,"M2 commission excites M1 Id");
    if(!dut.comm_busy || dut.physical_motor_mask!==3)$fatal(1,"runtime test mask blocked commission override");
    if(axis==1 && ({en2,en1}!==1 || pwm!==12'h03f))$fatal(1,"real M1 FSM physical output missing");
    if(axis==2 && ({en2,en1}!==2 || pwm!==12'hfc0))$fatal(1,"real M2 FSM physical output missing");
   end
   if(dut.comm_failed)$fatal(1,"real commissioning failed");
   if((dut.comm_mask & axis)==axis)n=150;
  end
  if((dut.comm_mask & axis)!=axis)$fatal(1,"commission never completed");
  force dut.drive.running=0;
 end
 endtask
 initial begin
  cfg[217:216]=1;cfg[221:220]=2;
  repeat(4)@(negedge clk);rst=1;repeat(5)@(negedge clk);
  force dut.peripheral_rst_n=1;force dut.cfg=cfg;
  force dut.commission_start=start;force dut.commission_select=select;
  force dut.drive.calibrated=1;force dut.drive.feedback_valid=1;force dut.drive.faults=0;
  force dut.drive.phase_currents={-16'sd512,-16'sd512,16'sd1024,-16'sd512,-16'sd512,16'sd1024};
  force dut.drive.mechanical_angles=angles;force dut.drive.core_en=3;force dut.drive.core_pwm=12'hfff;
  commission(1);commission(2);
  repeat(5)@(negedge clk);
  if(dut.drive.core.voltage_limit!==4096 || dut.drive.core.q_voltage_limit!==24576)$fatal(1,"runtime voltage ceilings changed after commissioning");
  if(dut.comm_mask!==3)$fatal(1,"dual calibration not retained");
  $display("PASS real M1/M2 commissioning FSMs drive only selected physical EN/PWM despite M2 runtime config");$finish;
 end
 initial begin #200000;$fatal(1,"timeout");end
endmodule
