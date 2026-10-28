`timescale 1ns/1ps
module tb_m2_trace;
reg clk=0;always #10 clk=~clk;reg rst=0;wire [255:0] sample;
motor_adapter_core #(.TRACE_MOTOR2(1),.MOTOR_MASK(3)) dut(
.clk(clk),.rst_n(rst),.arm(1'b0),.clear_fault(1'b0),.calibrate(1'b0),.estop(1'b0),
.id_ref_1(16'sd11),.iq_ref_1(16'sd22),.id_ref_2(-16'sd111),.iq_ref_2(16'sd222),
.current_trip_q15(16'd4096),.diagnostic_m1_sample(sample));
initial begin
force dut.feedback_valid=0;force dut.running=1;
force dut.feedback_currents={16'h3333,16'h2222,16'h1111,16'haaaa,16'hbbbb,16'hcccc};
force dut.captured_angle1=14'd100;force dut.captured_angle2=14'd200;
force dut.foc_theta_1=16'h1234;force dut.foc_theta_2=16'h5678;
force dut.park_valid_1=1;force dut.pi_valid_1=1;force dut.park_id_1=16'sd1;force dut.park_iq_1=16'sd2;
force dut.pi_ud_1=16'sd3;force dut.pi_uq_1=16'sd4;
force dut.park_valid_2=0;force dut.pi_valid_2=0;force dut.park_id_2=-16'sd101;force dut.park_iq_2=16'sd202;
force dut.pi_ud_2=-16'sd303;force dut.pi_uq_2=16'sd404;
repeat(3)@(negedge clk);rst=1;@(negedge clk);force dut.feedback_valid=1;
@(negedge clk);force dut.feedback_valid=0;force dut.park_valid_2=1;force dut.pi_valid_2=1;
@(negedge clk);#1;
if(sample[79:64]!=200 || sample[95:80]!=16'h5678 || sample[143:96]!={16'h3333,16'h2222,16'h1111})$fatal(1,"wrong motor input trace");
if($signed(sample[159:144])!=-111 || sample[175:160]!=222)$fatal(1,"wrong reference trace");
if($signed(sample[199:184])!=-101 || sample[215:200]!=202 || $signed(sample[231:216])!=-303 || sample[247:232]!=404)$fatal(1,"wrong IP feedback trace");
if(!sample[248])$fatal(1,"missing coherent Park data");
$display("PASS dual-motor diagnostic selects coherent M2 angle, currents, refs and real-IP Park/PI ports");$finish;
end
endmodule
