`timescale 1ns/1ps
module tb_dual_current;
 reg clk=0;always #10 clk=~clk;reg rst=0;
 motor_safe_drive #(.TUNING_KP_MAX(16384),.TUNING_KI_MAX(256),.INDEPENDENT_TUNING(1),.MOTOR_MASK(3),.ALLOW_CURRENT_TUNING(1),.DUAL_IQ_CONTROL(1)) dut(
 .clk(clk),.rst_n(rst),.request_arm(1'b0),.clear_fault(1'b0),.calibrate(1'b0),.estop(1'b0),
 .command_valid(1'b0),.commission_start(1'b0),.iq_request_1(16'sd0),.iq_request_2(16'sd0),
 .drv_fault_n(2'b11),.adc_busy(1'b0),.adc_dout_a(1'b0),.adc_dout_b(1'b0),.enc1_do(1'b0),.enc2_do(1'b0),
 .tuning_kp_m2(16'd700),.tuning_ki_m2(16'd9),.tuning_kp(16'd16384),.tuning_ki(16'd256));
 initial begin repeat(3)@(negedge clk);rst=1;
 force dut.iq1=16'sd123;force dut.iq2=-16'sd321;force dut.comm_busy=0;#1;
 if(dut.core.id_ref_1!==0 || dut.core.id_ref_2!==0 || dut.core.iq_ref_1!==123 || dut.core.iq_ref_2!==-321)
 $fatal(1,"dual torque lanes became single-motor Id/Iq");
 force dut.comm_busy=1;#1;if(dut.core.id_ref_1!==123 || dut.core.iq_ref_1!==0 || dut.core.iq_ref_2!==0)
 $fatal(1,"commissioning routing changed");
 force dut.comm_busy=2;#1;if(dut.core.id_ref_2!==-321 || dut.core.iq_ref_1!==0 || dut.core.iq_ref_2!==0)
 $fatal(1,"M2 commissioning routing changed");
 force dut.comm_busy=0;force dut.use_commission_gains=0;repeat(4)@(negedge clk);
 if(dut.core.foc1.kp!==16384 || dut.core.foc1.ki!==256 || dut.core.foc2.kp!==700 || dut.core.foc2.ki!==9)$fatal(1,"independent gains crossed");
 force dut.lifecycle_arm=1;force dut.tuning_kp_m2=16'd888;repeat(4)@(negedge clk);
 if(dut.core.foc2.kp!==700)$fatal(1,"live gains changed");
 force dut.lifecycle_arm=0;repeat(4)@(negedge clk);
 if(dut.core.foc2.kp!==888 || dut.core.foc1.kp!==16384)$fatal(1,"stopped update crossed axes");
 force dut.use_commission_gains=1;#1;
 if(dut.core.foc1.kp!==300 || dut.core.foc2.kp!==300 || dut.core.foc2.ki!==16)$fatal(1,"commission gain override lost");
 $display("PASS independent dual Iq, zero runtime Id, exclusive commissioning");$finish;end
endmodule
