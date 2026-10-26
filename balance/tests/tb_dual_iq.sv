`timescale 1ns/1ps
module tb_dual_iq;
 reg clk=0;always #10 clk=~clk;reg rst=0;
 motor_safe_drive #(.MOTOR_MASK(3),.ALLOW_CURRENT_TUNING(1),.DUAL_IQ_CONTROL(1)) dut(
 .clk(clk),.rst_n(rst),.request_arm(1'b0),.clear_fault(1'b0),.calibrate(1'b0),.estop(1'b0),
 .command_valid(1'b0),.commission_start(1'b0),.iq_request_1(16'sd0),.iq_request_2(16'sd0),
 .drv_fault_n(2'b11),.adc_busy(1'b0),.adc_dout_a(1'b0),.adc_dout_b(1'b0),.enc1_do(1'b0),.enc2_do(1'b0),
 .tuning_kp(16'd16384),.tuning_ki(16'd256));
 initial begin repeat(3)@(negedge clk);rst=1;
 force dut.iq1=16'sd123;force dut.iq2=-16'sd321;force dut.comm_busy=0;#1;
 if(dut.core.id_ref_1!==0 || dut.core.id_ref_2!==0 || dut.core.iq_ref_1!==123 || dut.core.iq_ref_2!==-321)
 $fatal(1,"dual torque lanes became single-motor Id/Iq");
 force dut.comm_busy=1;#1;if(dut.core.id_ref_1!==123 || dut.core.iq_ref_1!==0 || dut.core.iq_ref_2!==0)
 $fatal(1,"commissioning routing changed");
 force dut.comm_busy=2;#1;if(dut.core.id_ref_2!==-321 || dut.core.iq_ref_1!==0 || dut.core.iq_ref_2!==0)
 $fatal(1,"M2 commissioning routing changed");
 $display("PASS independent dual Iq, zero runtime Id, exclusive commissioning");$finish;end
endmodule
